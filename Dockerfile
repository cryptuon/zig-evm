FROM ubuntu:24.04 AS builder

RUN apt-get update && apt-get install -y wget xz-utils && rm -rf /var/lib/apt/lists/*

# Install Zig 0.15.2
RUN wget -q https://ziglang.org/download/0.15.2/zig-0.15.2-x86_64-linux.tar.xz && \
    tar xf zig-0.15.2-x86_64-linux.tar.xz && \
    mv zig-0.15.2-x86_64-linux /opt/zig && \
    rm zig-0.15.2-x86_64-linux.tar.xz

ENV PATH="/opt/zig:${PATH}"

WORKDIR /app
COPY . .

RUN zig build build-web -Doptimize=ReleaseFast

FROM ubuntu:24.04
COPY --from=builder /app/zig-out/bin/zig-evm-web /usr/local/bin/zig-evm-web

EXPOSE 3000
ENV PORT=3000

CMD ["zig-evm-web"]
