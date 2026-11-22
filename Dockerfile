# Image du serveur dédié. Attend l'export Godot dans build/server/
# x86 : SERVER_BIN=arena_server.x86_64 (défaut) / ARM : SERVER_BIN=arena_server.arm64
FROM debian:bookworm-slim

ARG SERVER_BIN=arena_server.x86_64
ENV SERVER_BIN=${SERVER_BIN}

RUN useradd --create-home arena
WORKDIR /app
COPY build/server/ ./
RUN chmod +x "./${SERVER_BIN}"

USER arena
EXPOSE 7777/udp
ENTRYPOINT ["sh", "-c", "exec ./${SERVER_BIN} --headless -- --server \"$@\"", "--"]
