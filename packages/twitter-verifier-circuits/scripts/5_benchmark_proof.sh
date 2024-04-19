#!/bin/bash
# set -e
source circuit.env

SAMPLE_SIZE=10
PROVER_NUM=32
TIME=(/usr/bin/time -f "mem %M\ntime %e\ncpu %P")
NODE=/home/okxdex/.nvm/versions/node/v21.6.2/bin/node
SNARKJS=/home/okxdex/.nvm/versions/node/v21.6.2/bin/snarkjs
RS_PATH=/home/okxdex/data/zkdex-pap/services/rapidsnark
prover=${RS_PATH}/build_prover/src/prover
proverServer=${RS_PATH}/build_nodejs/proverServerSingleThread
GPUProver=${RS_PATH}/build_prover_gpu/src/prover
REQ=${RS_PATH}/tools/request.js
export LD_LIBRARY_PATH=${RS_PATH}/depends/pistache/build/src

avg_time() {
  #
  # usage: avg_time n command ...
  #
  n=$1
  shift
  (($# > 0)) || return # bail if no command given
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
  avg_time $SAMPLE_SIZE $NODE $SNARKJS groth16 prove "$BUILD_DIR"/"$CIRCUIT_NAME".zkey "$BUILD_DIR"/witness.wtns "$BUILD_DIR"/proof.json "$BUILD_DIR"/public.json
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
  echo "Prover Number =" $PROVER_NUM
  pushd "$BUILD_DIR" >/dev/null
  mkdir -p build

  pushd "$CIRCUIT_NAME"_cpp/ >/dev/null
  make -j12
  cp "$CIRCUIT_NAME" ../build/
  popd >/dev/null

  # Copy witness and input
  cp witness.wtns ./build/"$CIRCUIT_NAME".wtns
  cp ../../inputs/input.json ./build/input_"$CIRCUIT_NAME".json

  # Start many prover servers in the background
  prover_pids=()
  rm -r logs
  mkdir -p logs
  for ((i = 0; i < ${PROVER_NUM}; i++)); do
    port=$((9000 + i))
    # Kill the proverServer if it is running
    kill -9 $(lsof -t -i:${port}) >/dev/null 2>&1 || true

    ${proverServer} $port "$CIRCUIT_NAME".zkey >./logs/${port}.log 2>&1 &
    # Save the PIDs of the prover servers to kill them later
    prover_pids+=($!)
  done
  echo "Prover server PIDs: ${prover_pids[@]}"

  # Give the servers some time to start
  sleep 5

  # Start many requests to each prover server concurrently
  start_time=$(date +%s)
  req_pids=()
  for ((i = 0; i < ${PROVER_NUM}; i++)); do
    port=$((9000 + i))
    $NODE ${REQ} ./build/input_$CIRCUIT_NAME.json $CIRCUIT_NAME $port >./logs/req-${i}.log 2>&1 &
    req_pids+=($!)
  done
  echo "Request PIDs: ${req_pids[@]}"
  for ((i = 0; i < ${PROVER_NUM}; i++)); do
    wait ${req_pids[i]}
  done
  end_time=$(date +%s)
  elapsed_time=$((end_time - start_time))

  for ((i = 0; i < ${PROVER_NUM}; i++)); do
    port=$((9000 + i))
    start_time=$(grep '\[TRACE\]: FullProver::thread_calculateProve start$' ./logs/${port}.log | awk '{print $4}')
    end_time=$(grep '\[TRACE\]: FullProver::thread_calculateProve end$' ./logs/${port}.log | awk '{print $4}')
    start_seconds=$(date -d"$start_time" +%s)
    end_seconds=$(date -d"$end_time" +%s)
    diff=$((end_seconds - start_seconds))
    echo "Prover $i: ${diff}"
  done

  # for ((i = 0; i < ${PROVER_NUM}; i++)); do
  #   ps_output=$(ps -p ${prover_pids[i]} -o %cpu,vsz,etimes --no-headers)
  #   echo $ps_output
  #   avg_cpu=$(echo $ps_output | awk '{print $1"%"}')
  #   avg_mem=$(echo $ps_output | awk '{$2=int($2/1024)"M"; print $2}')
  #   etime=$(echo $ps_output | awk '{print $3"s"}')
  #   echo "mem ${avg_mem}"
  #   echo "time ${etime}"
  #   echo "cpu ${avg_cpu}"

  #   echo mem ${avg_mem}
  #   echo time ${etime}
  #   echo cpu ${avg_cpu}
  # done

  # Kill the prover servers
  for pid in "${prover_pids[@]}"; do
    kill $pid
  done
  popd >/dev/null
}

echo "Sample Size =" $SAMPLE_SIZE
# echo "========== GPU RapidSnark standalone prove  =========="
# GPURapidStandalone

# echo "========== RapidSnark standalone prove  =========="
# RapidStandalone

echo "========== RapidSnark server prove  =========="
RapidServer

# echo "========== SnarkJS prove  =========="
# SnarkJS
