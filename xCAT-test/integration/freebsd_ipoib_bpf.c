/*
 * Compile with the configured dhcpcd source, src/bpf.c and -lpcap on FreeBSD.
 * The stubs capture the filters and frames submitted to the kernel boundary.
 */
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <net/if.h>
#include <net/bpf.h>
#include <netinet/in.h>
#include <netinet/if_ether.h>
#include <pcap.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "config.h"
#include "if.h"
#include "bpf.h"

static struct bpf_insn read_filter[128], write_filter[128];
static struct bpf_program read_program = { .bf_insns = read_filter };
static struct bpf_program write_program = { .bf_insns = write_filter };
static unsigned char sent[1024];
static size_t sent_len;
static unsigned int checks, failures;

static void
check(int ok, const char *name)
{
	printf("%s %u - %s\n", ok ? "ok" : "not ok", ++checks, name);
	if (!ok)
		failures++;
}

int
bpf_setfilter(const struct bpf *bpf, void *filter, unsigned int count)
{
	(void)bpf;
	if (count > 128)
		return -1;
	memcpy(read_filter, filter, count * sizeof(read_filter[0]));
	read_program.bf_len = count;
	return 0;
}

int
bpf_setwfilter(const struct bpf *bpf, void *filter, unsigned int count)
{
	(void)bpf;
	if (count > 128)
		return -1;
	memcpy(write_filter, filter, count * sizeof(write_filter[0]));
	write_program.bf_len = count;
	return 0;
}

int
bpf_lockfilter(const struct bpf *bpf)
{
	(void)bpf;
	return 0;
}

ssize_t
bpf_writev(const struct bpf *bpf, struct iovec *iov, int count)
{
	(void)bpf;
	sent_len = 0;
	for (int i = 0; i < count; i++) {
		if (iov[i].iov_len > sizeof(sent) - sent_len)
			return -1;
		if (iov[i].iov_len)
			memcpy(sent + sent_len, iov[i].iov_base, iov[i].iov_len);
		sent_len += iov[i].iov_len;
	}
	return (ssize_t)sent_len;
}

static int
accepts(const struct bpf_program *program, const unsigned char *packet, size_t caplen)
{
	struct pcap_pkthdr header = { .caplen = caplen, .len = 14 + 20 + 8 + 244 };
	return pcap_offline_filter(program, &header, packet) != 0;
}

int
main(void)
{
	struct interface ifp = {0};
	struct bpf bpf = { .bpf_ifp = &ifp };
	unsigned char packet[14 + 20 + 8 + 244] = {0};
	const unsigned char payload[] = {0x45, 0x00, 0x42};
	const unsigned char broadcast[] = {255, 255, 255, 255, 255, 255};
	const unsigned char zero[] = {0, 0, 0, 0, 0, 0};

	for (unsigned int kind = 0; kind < 2; kind++) {
		ifp.hwtype = kind ? ARPHRD_INFINIBAND : ARPHRD_ETHER;
		ifp.hwlen = kind ? 20 : 6;
		memset(ifp.hwaddr, 0x42, ifp.hwlen);
		check(bpf_frame_header_len(&ifp) == 14, "BPF header has Ethernet length");
		check(bpf_send(&bpf, ETHERTYPE_IP, payload, sizeof(payload)) == 17,
		    "broadcast send includes the BPF header");
		check(sent_len == 17 && memcmp(sent, broadcast, 6) == 0 &&
		    memcmp(sent + 6, kind ? zero : ifp.hwaddr, 6) == 0 &&
		    sent[12] == 8 && sent[13] == 0 &&
		    memcmp(sent + 14, payload, sizeof(payload)) == 0,
		    "broadcast framing preserves the IP payload");
		int installed = bpf_filter_bootp(&bpf, NULL);
		check(installed == 0, "read and write filters are generated");
		if (installed != 0)
			continue;
		memset(packet, 0, sizeof(packet));
		packet[12] = 8;
		packet[14] = 0x45;
		packet[23] = IPPROTO_UDP;
		packet[35] = 67;
		packet[37] = 68;
		check(accepts(&read_program, packet, sizeof(packet)),
		    "DHCP server replies pass the receive filter");
		packet[37] = 69;
		check(!accepts(&read_program, packet, sizeof(packet)),
		    "another UDP destination is rejected");
		packet[37] = 68;
		packet[21] = 1;
		check(!accepts(&read_program, packet, sizeof(packet)),
		    "noninitial IPv4 fragments are rejected");
		packet[21] = 0;
		check(!accepts(&read_program, packet, 13),
		    "a truncated link header is rejected");
		packet[35] = 68;
		packet[37] = 67;
		check(accepts(&write_program, packet, sizeof(packet)),
		    "DHCP client requests pass the write filter");
		packet[23] = IPPROTO_TCP;
		check(!accepts(&write_program, packet, sizeof(packet)),
		    "non-DHCP traffic is rejected by the write filter");
	}
	ifp.hwtype = ARPHRD_IEEE1394;
	check(bpf_filter_bootp(&bpf, NULL) == -1 && errno == EINVAL,
	    "unsupported link types remain rejected");
	printf("1..%u\n", checks);
	return failures ? EXIT_FAILURE : EXIT_SUCCESS;
}
