#!/bin/bash
set -e
# Tries to generate a non-chunked zkey
# You need to set entropy.env for this to work

source circuit.env

R1CS_FILE="$BUILD_DIR/$CIRCUIT_NAME.r1cs"
PARTIAL_ZKEYS="$BUILD_DIR"/partial_zkeys
PHASE1=$PTAU
source entropy.env

if [ ! -d "$BUILD_DIR"/partial_zkeys ]; then
    echo "No partial_zkeys directory found. Creating partial_zkeys directory..."
    mkdir -p "$BUILD_DIR"/partial_zkeys
fi

# Then, nonchunked snarkjs
yarn remove snarkjs
# mv ../yarn.lock ../yarn.lock_old2
# rm -rf ../../../node_modules_old2
# mv ../../../node_modules ../../../node_modules_old2
yarn add snarkjs@latest

echo "****GENERATING ZKEY NONCHUNKED 0****"
start=$(date +%s)
set -x
NODE_OPTIONS='--max-old-space-size=56000' node ../node_modules/.bin/snarkjs groth16 setup "$R1CS_FILE" "$PHASE1" "$PARTIAL_ZKEYS"/"$CIRCUIT_NAME"_0.zkey -e=$ENTROPY1
{ set +x; } 2>/dev/null
end=$(date +%s)
echo "DONE ($((end - start))s)"
echo

echo "****GENERATING ZKEY NONCHUNKED 1****"
start=$(date +%s)
set -x
NODE_OPTIONS='--max-old-space-size=56000' node ../node_modules/.bin/snarkjs zkey contribute "$PARTIAL_ZKEYS"/"$CIRCUIT_NAME"_0.zkey "$PARTIAL_ZKEYS"/"$CIRCUIT_NAME"_1.zkey --name="1st Contributor Name" -v -e=$ENTROPY2
{ set +x; } 2>/dev/null
end=$(date +%s)
echo "DONE ($((end - start))s)"
echo

echo "****GENERATING ZKEY NONCHUNKED FINAL****"
start=$(date +%s)
set -x
NODE_OPTIONS='--max-old-space-size=56000' node ../node_modules/.bin/snarkjs zkey beacon "$PARTIAL_ZKEYS"/"$CIRCUIT_NAME"_1.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_nonchunked.zkey $BEACON 10 -n="Final Beacon phase2" -v
{ set +x; } 2>/dev/null
end=$(date +%s)
echo "DONE ($((end - start))s)"
echo

yarn remove snarkjs
# mv ../yarn.lock ../yarn.lock_old3
# rm -rf ../../../node_modules_old3
# mv ../../../node_modules ../../../node_modules_old3
yarn add snarkjs@git+https://github.com/vb7401/snarkjs.git#24981febe8826b6ab76ae4d76cf7f9142919d2b8
yarn
