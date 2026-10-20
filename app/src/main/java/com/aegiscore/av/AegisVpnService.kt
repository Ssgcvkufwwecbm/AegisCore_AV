package com.aegiscore.av

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.ParcelFileDescriptor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

data class BlockedEntry(val id: Long, val domain: String, val type: String, val reason: String, val time: Long)
data class ShieldStats(val total: Long = 0, val blocked: Long = 0)

private data class DnsQuestion(val name: String, val type: Int, val end: Int)

private fun u16(b: ByteArray, o: Int): Int = ((b[o].toInt() and 0xFF) shl 8) or (b[o + 1].toInt() and 0xFF)

private object DnsCodec {
    /** Parses the first question of a DNS query. Returns null for anything malformed. */
    fun parseQuestion(d: ByteArray): DnsQuestion? {
        if (d.size < 17) return null
        if (u16(d, 4) < 1) return null
        var i = 12
        val sb = StringBuilder()
        while (true) {
            if (i >= d.size) return null
            val l = d[i].toInt() and 0xFF
            if (l == 0) { i++; break }
            if ((l and 0xC0) != 0) return null // compression pointers are not valid in a query question
            if (i + 1 + l > d.size) return null
            if (sb.isNotEmpty()) sb.append('.')
            for (k in 0 until l) sb.append((d[i + 1 + k].toInt() and 0xFF).toChar())
            i += 1 + l
        }
        if (i + 4 > d.size) return null
        return DnsQuestion(sb.toString().lowercase(), u16(d, i), i + 4)
    }

    /** Header + question only, QR=1, RA=1, RCODE=3 (NXDOMAIN), no answers. */
    fun nxdomain(query: ByteArray, end: Int): ByteArray {
        val r = query.copyOf(end)
        r[2] = (0x80 or (query[2].toInt() and 0x01)).toByte()
        r[3] = 0x83.toByte()
        for (k in 6..11) r[k] = 0
        return r
    }

    fun typeName(t: Int): String = when (t) {
        1 -> "A"; 2 -> "NS"; 5 -> "CNAME"; 12 -> "PTR"; 15 -> "MX"
        16 -> "TXT"; 28 -> "AAAA"; 33 -> "SRV"; 65 -> "HTTPS"
        else -> "TYPE$t"
    }
}

/**
 * Local DNS sinkhole. The tunnel only claims a fake DNS server address (10.99.0.2/32), so just DNS
 * lookups enter the TUN; all other traffic keeps using the normal network. Every UDP/53 packet is
 * parsed, checked against ThreatIntel and either answered with NXDOMAIN or forwarded (via a
 * protect()ed socket) to the real resolver.
 */
class AegisVpnService : VpnService() {

    companion object {
        const val ACTION_STOP = "com.aegiscore.av.STOP_SHIELD"
        private const val VPN_ADDR = "10.99.0.1"
        private const val FAKE_DNS = "10.99.0.2"
        private const val MAX_LOG = 300

        private val _running = MutableStateFlow(false)
        val running: StateFlow<Boolean> = _running.asStateFlow()

        private val _stats = MutableStateFlow(ShieldStats())
        val stats: StateFlow<ShieldStats> = _stats.asStateFlow()

        private val _blocked = MutableStateFlow<List<BlockedEntry>>(emptyList())
        val blocked: StateFlow<List<BlockedEntry>> = _blocked.asStateFlow()

        private val idGen = AtomicLong()

        fun start(ctx: Context) {
            ctx.startService(Intent(ctx, AegisVpnService::class.java))
        }

        fun stop(ctx: Context) {
            ctx.startService(Intent(ctx, AegisVpnService::class.java).setAction(ACTION_STOP))
        }
    }

    @Volatile private var active = false
    private var tun: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private var pool: ExecutorService? = null
    private var upstreams: List<InetAddress> = emptyList()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            teardown()
            stopSelf()
            return START_NOT_STICKY
        }
        if (!active) startShield()
        return START_STICKY
    }

    override fun onRevoke() {
        teardown()
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        teardown()
        super.onDestroy()
    }

    private fun startShield() {
        upstreams = discoverUpstreams()
        val pfd = try {
            Builder()
                .setSession("AegisCore Shield")
                .setMtu(1500)
                .addAddress(VPN_ADDR, 24)
                .addDnsServer(FAKE_DNS)
                .addRoute(FAKE_DNS, 32)
                .setBlocking(true)
                .establish()
        } catch (e: Exception) {
            null
        }
        if (pfd == null) {
            teardown()
            stopSelf()
            return
        }
        tun = pfd
        active = true
        _running.value = true
        pool = Executors.newFixedThreadPool(6)
        worker = Thread({ packetLoop(pfd) }, "aegis-dns").also { it.start() }
    }

    private fun teardown() {
        active = false
        try { worker?.interrupt() } catch (e: Exception) { }
        try { tun?.close() } catch (e: Exception) { }
        tun = null
        worker = null
        pool?.shutdownNow()
        pool = null
        _running.value = false
    }

    /** System resolvers of the underlying network (captured before the tunnel exists), then public fallbacks. */
    private fun discoverUpstreams(): List<InetAddress> {
        val found: List<InetAddress> = try {
            val cm = getSystemService(ConnectivityManager::class.java)
            val lp = cm.getLinkProperties(cm.activeNetwork)
            lp?.dnsServers?.filter { it.hostAddress != FAKE_DNS } ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
        val fallback = listOf(
            InetAddress.getByAddress(byteArrayOf(1, 1, 1, 1)),
            InetAddress.getByAddress(byteArrayOf(9, 9, 9, 9))
        )
        return found + fallback
    }

    private fun packetLoop(pfd: ParcelFileDescriptor) {
        val input = FileInputStream(pfd.fileDescriptor)
        val output = FileOutputStream(pfd.fileDescriptor)
        val buf = ByteArray(32767)
        try {
            while (active) {
                val n = input.read(buf)
                if (n < 0) break
                if (n > 0) handlePacket(buf, n, output)
            }
        } catch (e: IOException) {
            // tunnel closed
        } finally {
            if (active) {
                teardown()
                stopSelf()
            }
        }
    }

    private fun handlePacket(p: ByteArray, len: Int, out: FileOutputStream) {
        if (len < 28) return
        if ((p[0].toInt() ushr 4) != 4) return                 // IPv4 only (tunnel has no IPv6 address)
        val ihl = (p[0].toInt() and 0x0F) * 4
        if (ihl < 20 || len < ihl + 8) return
        if ((p[9].toInt() and 0xFF) != 17) return              // UDP only
        if (u16(p, ihl + 2) != 53) return                      // DNS only
        val srcPort = u16(p, ihl)
        val total = minOf(u16(p, 2), len)
        val dnsLen = total - ihl - 8
        if (dnsLen < 12) return

        val dns = p.copyOfRange(ihl + 8, ihl + 8 + dnsLen)
        val clientIp = p.copyOfRange(12, 16)
        val serverIp = p.copyOfRange(16, 20)

        _stats.update { it.copy(total = it.total + 1) }
        val q = DnsCodec.parseQuestion(dns)
        if (q != null) {
            val reason = ThreatIntel.check(q.name)
            if (reason != null) {
                record(q, reason)
                writeUdp(out, serverIp, clientIp, srcPort, DnsCodec.nxdomain(dns, q.end))
                return
            }
        }
        try {
            pool?.execute {
                val resp = forward(dns)
                if (resp != null) writeUdp(out, serverIp, clientIp, srcPort, resp)
            }
        } catch (e: Exception) {
            // pool already shut down
        }
    }

    private fun record(q: DnsQuestion, reason: String) {
        val e = BlockedEntry(idGen.incrementAndGet(), q.name, DnsCodec.typeName(q.type), reason, System.currentTimeMillis())
        _blocked.update { (listOf(e) + it).take(MAX_LOG) }
        _stats.update { it.copy(blocked = it.blocked + 1) }
    }

    private fun forward(query: ByteArray): ByteArray? {
        for (server in upstreams) {
            val s = DatagramSocket()
            try {
                protect(s)
                s.soTimeout = 3500
                s.connect(InetSocketAddress(server, 53))
                s.send(DatagramPacket(query, query.size))
                val rb = ByteArray(4096)
                val rp = DatagramPacket(rb, rb.size)
                s.receive(rp)
                return rb.copyOf(rp.length)
            } catch (e: Exception) {
                // try the next resolver
            } finally {
                s.close()
            }
        }
        return null
    }

    private fun checksum(b: ByteArray, off: Int, len: Int): Int {
        var sum = 0L
        var i = off
        while (i < off + len - 1) {
            sum += (((b[i].toInt() and 0xFF) shl 8) or (b[i + 1].toInt() and 0xFF)).toLong()
            i += 2
        }
        while ((sum shr 16) != 0L) sum = (sum and 0xFFFF) + (sum shr 16)
        return (sum.inv() and 0xFFFF).toInt()
    }

    /** Wraps [payload] in IPv4 + UDP (source port 53) and writes it back into the tunnel. */
    private fun writeUdp(out: FileOutputStream, srcIp: ByteArray, dstIp: ByteArray, dstPort: Int, payload: ByteArray) {
        val total = 20 + 8 + payload.size
        val pkt = ByteArray(total)
        pkt[0] = 0x45
        pkt[2] = (total shr 8).toByte()
        pkt[3] = total.toByte()
        pkt[6] = 0x40                       // DF
        pkt[8] = 64                         // TTL
        pkt[9] = 17                         // UDP
        System.arraycopy(srcIp, 0, pkt, 12, 4)
        System.arraycopy(dstIp, 0, pkt, 16, 4)
        val ck = checksum(pkt, 0, 20)
        pkt[10] = (ck shr 8).toByte()
        pkt[11] = ck.toByte()
        pkt[21] = 53                        // UDP source port 53 (pkt[20] stays 0)
        pkt[22] = (dstPort shr 8).toByte()
        pkt[23] = dstPort.toByte()
        val udpLen = 8 + payload.size
        pkt[24] = (udpLen shr 8).toByte()
        pkt[25] = udpLen.toByte()           // UDP checksum 0 = none (valid over IPv4)
        System.arraycopy(payload, 0, pkt, 28, payload.size)
        try {
            synchronized(out) { out.write(pkt) }
        } catch (e: IOException) {
            // tunnel closed
        }
    }
}
