# Copyright (c) 2017 Takayuki Imada <takayuki.imada@gmail.com>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

#! /bin/bash

# Parameters
BUFSIZE="64 128 256 512 1024 2048"
OCAMLVER="4.03.0"
ITERATIONS="10"
C_TAP="tap1"
S_TAP="tap0"

# The followings should not be modified
GUEST="Mirage"
NET="--net="
PLATFORM="unix"
PROTO=${1}

# Check a selected protocol
case ${PROTO} in
        "tcp" )
				APP="iperf";
        ;;
        "udp" )
				APP="iperf_udp";
        ;;
        * ) echo "Invalid protocol selected"; exit
esac

CURRENT_DIR=${PWD}
CLIENTPATH="./${APP}_client"
SERVERPATH="./${APP}_server"
CLIENTBIN="${APP}_client"
SERVERBIN="${APP}_server"

# Check the arguments provided
case ${PLATFORM} in
        "unix" )
                CMD_C="sudo ./${CLIENTPATH}/${CLIENTBIN}";
                CMD_S="sudo ./${SERVERPATH}/${SERVERBIN}";
        ;;
        * ) echo "Invalid hypervisor selected"; exit
esac

COMPILER="OCaml ${OCAMLVER}"

# switch an OCaml compiler version to be used
opam switch ${OCAMLVER}
eval `opam config env`

#   let nw = Ipaddr.V4.Prefix.of_address_string_exn "192.168.122.100/24" in
#  let gw = Some (Ipaddr.V4.of_string_exn "192.168.122.1") in

# Build and dispatch a server application
cd ${SERVERPATH}
make clean
mirage configure -t ${PLATFORM} --interface=${NET}${S_TAP} --ipv4="192.168.122.100/24" --ipv4-gateway="192.168.122.1"
make
cd ${CURRENT_DIR}
${CMD_S} &

# Dispatch a client side MirageOS VM repeatedly
JSONLOG="./${OCAMLVER}_${PLATFORM}_${APP}.json"
echo -n "{
  \"guest\": \"${GUEST}\",
  \"platform\": \"${PLATFORM}\",
  \"compiler\": \"${COMPILER}\",
  \"records\": [
" > ./${JSONLOG}

CLIENTLOG="${OCAMLVER}_${PLATFORM}_${APP}_client.log"
echo -n '' > ./${CLIENTLOG}

#   let nw = Ipaddr.V4.Prefix.of_address_string_exn "192.168.122.101/24" in
#  let gw = Some (Ipaddr.V4.of_string_exn "192.168.122.1") in

cd ${CLIENTPATH}
make clean
mirage configure -t ${PLATFORM} --interface=${NET}${C_TAP} --ipv4="192.168.122.101/24" --ipv4-gateway="192.168.122.1"
make
cd ${CURRENT_DIR}

for BUF in ${BUFSIZE}
do
        cd ${CLIENTPATH}
        sed -i -e "s/let\ blen\ =\ [0-9]*/let blen = ${BUF}/" ./unikernel.ml
        make
        cd ${CURRENT_DIR}

        echo -n "{ \"bufsize\": ${BUF}, \"throughput\": [" >> ./${JSONLOG}
        for i in $(seq 1 ${ITERATIONS});
        do
                echo "***** Testing iperf: Buffer size ${BUF}, ${i}/${ITERATIONS} *****"
				echo "${CURRENT_DIR}/${CLIENTPATH}"
                ${CMD_C} >> ${CLIENTLOG}
                TP=`sed -e 's/^M/\n/g' ./${CLIENTLOG} | grep Throughput | tail -n 1 | cut -d' ' -f 10`
                echo -n "${TP}," >> ./${JSONLOG}
        done
        echo -n "]}," >> ./${JSONLOG}
done

# Correct the generated JSON file
echo -n "]}" >> ./${JSONLOG}
sed -i -e 's/,\]/]/g' ${JSONLOG}
cat ./${JSONLOG} | jq

# Destroy the server application
sudo killall iperf
