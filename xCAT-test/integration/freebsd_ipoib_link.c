/*
 * Test-only getifaddrs fixture for an isolated Ethernet link on FreeBSD.
 * It exposes IPoIB metadata without replacing DHCP, BPF, sockets or routing.
 * This fixture does not qualify an InfiniBand fabric or hardware return path.
 */
#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/if_types.h>
#include <dlfcn.h>
#include <ifaddrs.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

struct replacement {
	struct replacement *next;
	struct ifaddrs *entry;
	struct sockaddr *original;
	struct sockaddr_storage storage;
};
static struct replacement *replacements;

int
getifaddrs(struct ifaddrs **result)
{
	int (*original)(struct ifaddrs **) = dlsym(RTLD_NEXT, "getifaddrs");
	const char *name = getenv("XCAT_FREEBSD_IPOIB_TEST_LINK");
	const char *kind = getenv("XCAT_FREEBSD_IPOIB_TEST_TYPE");
	const unsigned char address[20] = {
	    0, 0, 0, 0x5a, 0xfe, 0x80, 0, 0, 0, 0, 0, 0,
	    2, 0, 0, 0, 0, 0, 0, 9
	};
	int status = original(result);

	if (status || name == NULL)
		return status;
	for (struct ifaddrs *entry = *result; entry; entry = entry->ifa_next) {
		if (!entry->ifa_addr || entry->ifa_addr->sa_family != AF_LINK ||
		    strcmp(entry->ifa_name, name) != 0)
			continue;
		const struct sockaddr_dl *link = (void *)entry->ifa_addr;
		struct replacement *saved = calloc(1, sizeof(*saved));
		size_t length = offsetof(struct sockaddr_dl, sdl_data) +
		    link->sdl_nlen + sizeof(address);
		if (!saved)
			abort();
		if (length < link->sdl_len)
			length = link->sdl_len;
		if (length > sizeof(saved->storage))
			abort();
		struct sockaddr_dl *replacement = (void *)&saved->storage;
		memcpy(replacement, link, link->sdl_len);
		replacement->sdl_len = length;
		replacement->sdl_type = kind && strcmp(kind, "vlan") == 0 ?
		    IFT_L2VLAN : IFT_INFINIBAND;
		replacement->sdl_alen = sizeof(address);
		memcpy(LLADDR(replacement), address, sizeof(address));
		saved->entry = entry;
		saved->original = entry->ifa_addr;
		entry->ifa_addr = (void *)replacement;
		saved->next = replacements;
		replacements = saved;
	}
	return 0;
}

void
freeifaddrs(struct ifaddrs *list)
{
	void (*original)(struct ifaddrs *) = dlsym(RTLD_NEXT, "freeifaddrs");

	for (struct ifaddrs *entry = list; entry; entry = entry->ifa_next) {
		struct replacement **where = &replacements;
		while (*where) {
			struct replacement *saved = *where;
			if (saved->entry == entry) {
				entry->ifa_addr = saved->original;
				*where = saved->next;
				free(saved);
				break;
			}
			where = &saved->next;
		}
	}
	original(list);
}
