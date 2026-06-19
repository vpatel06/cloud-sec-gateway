# Use a pinned, minimal, secure Alpine base
FROM alpine:3.20

# Install WireGuard tools and iptables for routing, then clean cache
RUN apk add --no-cache wireguard-tools iptables iproute2

# Expose the standard WireGuard UDP port
EXPOSE 51820/udp

# Set the working directory for keys and configs
WORKDIR /etc/wireguard

# Start WireGuard and keep the container alive by watching a null stream
CMD ["sh", "-c", "wg-quick up wg0 && tail -f /dev/null"]