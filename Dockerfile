# Image du serveur dédié, multi-architecture (amd64 / arm64).
# Attend les exports Godot dans build/server/arena_server.<arch> (voir export_presets.cfg).
FROM debian:bookworm-slim

ARG TARGETARCH

RUN useradd --create-home arena
WORKDIR /app
COPY build/server/arena_server.${TARGETARCH} ./arena_server
RUN chmod +x ./arena_server

USER arena
EXPOSE 7777/udp
ENTRYPOINT ["./arena_server", "--headless", "--", "--server"]
