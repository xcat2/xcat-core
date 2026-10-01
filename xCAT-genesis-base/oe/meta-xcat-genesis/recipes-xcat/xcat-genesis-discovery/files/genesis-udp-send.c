// SPDX-License-Identifier: EPL-1.0

#define _POSIX_C_SOURCE 200112L

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

enum {
    SOURCE_PORT = 301,
    MAX_DATAGRAM = 65507,
};

int main(int argc, char **argv)
{
    struct addrinfo hints = { 0 };
    struct addrinfo *addresses = NULL;
    unsigned char packet[MAX_DATAGRAM + 1];
    char *end = NULL;
    long port;
    FILE *input;
    size_t length;
    int error;
    int last_error = 0;
    int socket_fd;
    int result = EXIT_FAILURE;

    if (argc != 4) {
        fprintf(stderr, "usage: %s packet host port\n", argv[0]);
        return EXIT_FAILURE;
    }

    errno = 0;
    port = strtol(argv[3], &end, 10);
    if (errno || !end || *end || port < 1 || port > UINT16_MAX) {
        fprintf(stderr, "invalid destination port: %s\n", argv[3]);
        return EXIT_FAILURE;
    }

    input = fopen(argv[1], "rb");
    if (!input) {
        perror("unable to open discovery packet");
        return EXIT_FAILURE;
    }
    length = fread(packet, 1, sizeof(packet), input);
    if (ferror(input) || length == 0 || length > MAX_DATAGRAM) {
        fprintf(stderr, "invalid discovery packet size\n");
        fclose(input);
        return EXIT_FAILURE;
    }
    fclose(input);

    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    error = getaddrinfo(argv[2], argv[3], &hints, &addresses);
    if (error != 0) {
        fprintf(stderr, "unable to resolve discovery endpoint: %s\n",
                gai_strerror(error));
        return EXIT_FAILURE;
    }

    for (struct addrinfo *address = addresses; address; address = address->ai_next) {
        struct sockaddr_storage source = { 0 };
        socklen_t source_length;

        if (address->ai_family == AF_INET) {
            struct sockaddr_in *source4 = (struct sockaddr_in *)&source;
            source4->sin_family = AF_INET;
            source4->sin_addr.s_addr = htonl(INADDR_ANY);
            source4->sin_port = htons(SOURCE_PORT);
            source_length = sizeof(*source4);
        } else if (address->ai_family == AF_INET6) {
            struct sockaddr_in6 *source6 = (struct sockaddr_in6 *)&source;
            source6->sin6_family = AF_INET6;
            source6->sin6_addr = in6addr_any;
            source6->sin6_port = htons(SOURCE_PORT);
            source_length = sizeof(*source6);
        } else {
            continue;
        }

        socket_fd = socket(address->ai_family, address->ai_socktype,
                           address->ai_protocol);
        if (socket_fd < 0) {
            last_error = errno;
            continue;
        }
        if (bind(socket_fd, (struct sockaddr *)&source, source_length) < 0) {
            last_error = errno;
            close(socket_fd);
            continue;
        }
        if (sendto(socket_fd, packet, length, 0, address->ai_addr,
                   address->ai_addrlen) == (ssize_t)length) {
            close(socket_fd);
            result = EXIT_SUCCESS;
            break;
        }
        last_error = errno;
        close(socket_fd);
    }
    if (result != EXIT_SUCCESS && last_error) {
        errno = last_error;
        perror("unable to send discovery packet");
    }

    freeaddrinfo(addresses);
    return result;
}
