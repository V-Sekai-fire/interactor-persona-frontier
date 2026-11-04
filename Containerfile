# The node on AlmaLinux 10 with datasource-store's weft_fdb VFS linked in: build stage with the
# Lean toolchain and FoundationDB's client library; run stage with the binary, the knowledge seed,
# the generated domain, Erlang for epmd, and the same client library. One process serves HTTP on
# 9920 and the Erlang node on 9930. Pages go to the cluster named by WEFT_FDB_CLUSTER_FILE when
# FRONTIER_DB is file:frontier?vfs=weft_fdb; without those, the store is a SQLite file at /data.
#
#   podman build -t frontier .
#   podman run --rm -p 9920:9920 -p 9930:9930 -p 4369:4369 -v frontier-data:/data \
#     -v /etc/foundationdb/fdb.cluster:/etc/foundationdb/fdb.cluster:ro \
#     -e FRONTIER_DB=file:frontier?vfs=weft_fdb -e WEFT_FDB_CLUSTER_FILE=/etc/foundationdb/fdb.cluster frontier
ARG FDB=7.3.63
FROM almalinux:10 AS build
ARG FDB
RUN dnf -y install gcc gcc-c++ make git curl-minimal ca-certificates && dnf clean all \
 && curl -sLo /tmp/fdb-clients.rpm https://github.com/apple/foundationdb/releases/download/${FDB}/foundationdb-clients-${FDB}-1.el9.$(uname -m).rpm \
 && rpm -i /tmp/fdb-clients.rpm && rm /tmp/fdb-clients.rpm
RUN curl -sSfL https://elan.lean-lang.org/elan-init.sh | sh -s -- -y --default-toolchain none
ENV PATH=/root/.elan/bin:$PATH
WORKDIR /src
COPY lean-toolchain lakefile.lean lake-manifest.json ./
RUN elan toolchain install "$(cat lean-toolchain)"
COPY Main.lean Witness.lean ./
COPY Frontier ./Frontier
COPY c ./c
COPY thirdparty ./thirdparty
COPY knowledge ./knowledge
RUN lake build -Kfdb=/usr/lib64/libfdb_c.so && ./.lake/build/bin/frontier_witness

FROM almalinux:10
ARG FDB
RUN dnf -y install erlang-erts erlang-kernel erlang-stdlib curl-minimal && dnf clean all \
 && curl -sLo /tmp/fdb-clients.rpm https://github.com/apple/foundationdb/releases/download/${FDB}/foundationdb-clients-${FDB}-1.el9.$(uname -m).rpm \
 && rpm -i /tmp/fdb-clients.rpm && rm /tmp/fdb-clients.rpm && dnf -y remove curl-minimal && dnf clean all
WORKDIR /app
COPY --from=build /src/.lake/build/bin/frontier /app/frontier
COPY knowledge ./knowledge
COPY domains ./domains
COPY plans ./plans
RUN mkdir -p /data && useradd -r -d /app frontier && chown -R frontier /app /data
USER frontier
ENV FRONTIER_DB=/data/frontier.sqlite
EXPOSE 9920 9930 4369
CMD ["sh", "-c", "[ -n \"$FRONTIER_COOKIE\" ] || [ -f /data/cookie ] || head -c 24 /dev/urandom | base64 > /data/cookie; epmd -daemon && exec /app/frontier --host 0.0.0.0 --port 9920 --dist-port 9930 ${FRONTIER_COOKIE:+--cookie $FRONTIER_COOKIE} ${FRONTIER_COOKIE:---cookie-file /data/cookie}"]
