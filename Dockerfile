# Use a pinned, minimal, secure Alpine base
FROM alpine:3.20

# Install WireGuard tools and iptables for routing, then clean cache
RUN apk add --no-cache wireguard-tools iptables iproute2

# Expose the standard WireGuard UDP port
EXPOSE 51820/udp

# Set the working directory for keys and configs
WORKDIR /etc/wireguard

# Start WireGuard in the foreground so Docker can monitor the process
CMD ["wg-quick", "up", "wg0"]