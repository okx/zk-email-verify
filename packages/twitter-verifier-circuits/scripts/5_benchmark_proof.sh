#!/bin/bash
set -e

source circuit.env

SAMPLE_SIZE=20
TIME=(/usr/bin/time -f "mem %M\ntime %e\ncpu %P")
RS_PATH=/home/okxdex/data/zkdex-pap/services/rapidsnark
prover=${RS_PATH}/build_prover/src/prover
proverServer=${RS_PATH}/build_nodejs/proverServer
GPUProver=${RS_PATH}/build_prover_gpu/src/prover
REQ=${RS_PATH}/tools/request.js
export LD_LIBRARY_PATH=${RS_PATH}/depends/pistache/build/src

avg_time() {
    #
    # usage: avg_time n command ...
    #
    n=$1; shift
    (($# > 0)) || return                   # bail if no command given
    echo "$@"
    for ((i = 0; i < n; i++)); do
        "${TIME[@]}" "$@" 2>&1
        # | tee /dev/stderr
    done | awk '
        /^mem [0-9]+/ { mem = mem + $2; nm++ }
        /^time [0-9]+\.[0-9]+/ { time = time + $2; nt++ }
        /^cpu [0-9]+%/  { cpu  = cpu  + substr($2,1,length($2)-1); nc++}
        END    {
             if (nm>0) printf("mem %d MB\n", mem/nm/1024);
             if (nt>0) printf("time %f s\n", time/nt);
             if (nc>0) printf("cpu %d \n",  cpu/nc)
           }'
}

function SnarkJS() {
  avg_time $SAMPLE_SIZE snarkjs groth16 prove "$BUILD_DIR"/"$CIRCUIT_NAME".zkey "$BUILD_DIR"/witness.wtns "$BUILD_DIR"/proof.json "$BUILD_DIR"/public.json
  proof_size=$(ls -lh "$BUILD_DIR"/proof.json | awk '{print $5}')
  echo "Proof size: $proof_size"
}

function RapidStandalone() {
  avg_time $SAMPLE_SIZE ${prover} "$BUILD_DIR"/"$CIRCUIT_NAME".zkey "$BUILD_DIR"/witness.wtns "$BUILD_DIR"/proof.json "$BUILD_DIR"/public.json
}

function GPURapidStandalone() {
  avg_time $SAMPLE_SIZE ${GPUProver} "$BUILD_DIR"/"$CIRCUIT_NAME".zkey "$BUILD_DIR"/witness.wtns "$BUILD_DIR"/proof.json "$BUILD_DIR"/public.json
}

function RapidServer() {
  pushd "$BUILD_DIR" > /dev/null
  mkdir -p build

  pushd "$CIRCUIT_NAME"_cpp/ > /dev/null
  make -j12
  cp "$CIRCUIT_NAME" ../build/
  popd > /dev/null

  # Copy witness and input
  cp witness.wtns ./build/"$CIRCUIT_NAME".wtns
  cp input.json ./build/input_"$CIRCUIT_NAME".json

  # Kill the proverServer if it is running on 9080 port
  kill -9 $(lsof -t -i:9080) > /dev/null 2>&1 || true
  # Start the prover server in the background
  ${proverServer} 9080 "$CIRCUIT_NAME".zkey > /dev/null 2>&1 &

  # Save the PID of the proverServer to kill it later
  PROVER_SERVER_PID=$!

  # Give the server some time to start
  sleep 1

  avg_t=$(avg_time $SAMPLE_SIZE node ${REQ} ./build/input_$CIRCUIT_NAME.json $CIRCUIT_NAME | grep "time")

  ps_output=$(ps -p `pidof proverServer` -o %cpu,vsz --no-headers)
  avg_cpu=$(echo $ps_output | awk '{print $1"%"}')
  avg_mem=$(echo $ps_output | awk '{$2=int($2/1024)"M"; print $2}')

  echo mem ${avg_mem}
  echo ${avg_t}
  echo cpu ${avg_cpu}

  # Kill the proverServer
  kill $PROVER_SERVER_PID
  popd > /dev/null
}

echo "Sample Size =" $SAMPLE_SIZE
echo "========== GPU RapidSnark standalone prove  =========="
GPURapidStandalone

echo "========== RapidSnark standalone prove  =========="
RapidStandalone

echo "========== RapidSnark server prove  =========="
RapidServer

echo "========== SnarkJS prove  =========="
SnarkJS
