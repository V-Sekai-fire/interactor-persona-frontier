# The node on AlmaLinux 10: build stage with the Lean toolchain, Erlang and SQLite headers; run
# stage with the binary, the knowledge seed, the generated domain, and Erlang for epmd. One
# process serves HTTP on 9920 and the Erlang node on 9930; the store is SQLite at /data.
#
#   podman build -t frontier .
#   podman run --rm -p 9920:9920 -p 9930:9930 -p 4369:4369 -v frontier-data:/data frontier
#
# FoundationDB is not in this image: mount datasource-store's libweftfdb and set FRONTIER_DB,
# FRONTIER_VFS_EXT and WEFT_FDB_CLUSTER_FILE to put the pages in a cluster beside it.
FROM almalinux:10 AS build
RUN dnf -y install gcc gcc-c++ make git curl-minimal sqlite-devel ca-certificates && dnf clean all
RUN curl -sSfL https://elan.lean-lang.org/elan-init.sh | sh -s -- -y --default-toolchain none
ENV PATH=/root/.elan/bin:$PATH
WORKDIR /src
COPY lean-toolchain lakefile.lean lake-manifest.json ./
RUN elan toolchain install "$(cat lean-toolchain)"
COPY Main.lean Witness.lean ./
COPY Frontier ./Frontier
COPY c ./c
COPY knowledge ./knowledge
RUN lake build && ./.lake/build/bin/frontier_witness

FROM almalinux:10
RUN dnf -y install sqlite-libs erlang-erts erlang-kernel erlang-stdlib && dnf clean all
WORKDIR /app
COPY --from=build /src/.lake/build/bin/frontier /app/frontier
COPY knowledge ./knowledge
COPY domains ./domains
COPY plans ./plans
RUN mkdir -p /data && useradd -r -d /app frontier && chown -R frontier /app /data
USER frontier
ENV FRONTIER_DB=/data/frontier.sqlite
EXPOSE 9920 9930 4369
# epmd first, in the background, then the node; the cookie comes from FRONTIER_COOKIE or a file at /data
CMD ["sh", "-c", "[ -n \"$FRONTIER_COOKIE\" ] || [ -f /data/cookie ] || head -c 24 /dev/urandom | base64 > /data/cookie; epmd -daemon && exec /app/frontier --host 0.0.0.0 --port 9920 --dist-port 9930 ${FRONTIER_COOKIE:+--cookie $FRONTIER_COOKIE} ${FRONTIER_COOKIE:---cookie-file /data/cookie}"]
