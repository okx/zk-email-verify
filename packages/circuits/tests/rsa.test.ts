import fs from "fs";
import { buildMimcSponge } from "circomlibjs";
import { wasm as wasm_tester } from "circom_tester";
import { Scalar } from "ffjavascript";
import path from "path";

import { DKIMVerificationResult } from "@zk-email/helpers/src/dkim";
import { generateCircuitInputs } from "@zk-email/helpers/src/input-helpers";
import { verifyDKIMSignature } from "@zk-email/helpers/src/dkim";
import { toCircomBigIntBytes } from "@zk-email/helpers/src/binaryFormat";


exports.p = Scalar.fromString(
  "21888242871839275222246405745257275088548364400416034343698204186575808495617"
);

describe("RSA", () => {
  jest.setTimeout(10 * 60 * 1000); // 10 minutes

  let circuit: any;
  let dkimResult: DKIMVerificationResult;

  beforeAll(async () => {
    circuit = await wasm_tester(
      path.join(__dirname, "./rsa-test.circom"),
      {
        // @dev During development recompile can be set to false if you are only making changes in the tests.
        // This will save time by not recompiling the circuit every time.
        // Compile: circom "./tests/email-verifier-test.circom" --r1cs --wasm --sym --c --wat --output "./tests/compiled-test-circuit"
        recompile: true,
        output: path.join(__dirname, "./compiled-test-circuit"),
        include: path.join(__dirname, "../../../node_modules"),
      }
    );
    const rawEmail = fs.readFileSync(path.join(__dirname, "./test.eml"));
    dkimResult = await verifyDKIMSignature(rawEmail);
  });

  it("should verify 2048 bit rsa signature correctly", async function () {
    const emailVerifierInputs = generateCircuitInputs({
      rsaSignature: dkimResult.signature,
      rsaPublicKey: dkimResult.publicKey,
      body: dkimResult.body,
      bodyHash: dkimResult.bodyHash,
      message: dkimResult.message,
      maxMessageLength: 640,
      maxBodyLength: 768,
    });


    const witness = await circuit.calculateWitness({
      signature: emailVerifierInputs.signature,
      modulus: emailVerifierInputs.pubkey,
      // TODO: generate this from the input
      base_message: ["1156466847851242602709362303526378170", "191372789510123109308037416804949834", "7204", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0"],
    });
    await circuit.checkConstraints(witness);
    await circuit.assertOut(witness, {})
  });

  it("should verify 1024 bit rsa signature correctly", async function () {
    const signature = toCircomBigIntBytes(
      BigInt(
        102386562682221859025549328916727857389789009840935140645361501981959969535413501251999442013082353139290537518086128904993091119534674934202202277050635907008004079788691412782712147797487593510040249832242022835902734939817209358184800954336078838331094308355388211284440290335887813714894626653613586546719n
      )
    );

    const pubkey = toCircomBigIntBytes(
      BigInt(
        106773687078109007595028366084970322147907086635176067918161636756354740353674098686965493426431314019237945536387044259034050617425729739578628872957481830432099721612688699974185290306098360072264136606623400336518126533605711223527682187548332314997606381158951535480830524587400401856271050333371205030999n
      )
    );

    const witness = await circuit.calculateWitness({
      signature: signature,
      modulus: pubkey,
      // TODO: generate this from the input
      base_message: ["1156466847851242602709362303526378170", "191372789510123109308037416804949834", "7204", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0"],
    });
    await circuit.checkConstraints(witness);
    await circuit.assertOut(witness, {});
  });

  it("should fail when verifying with an incorrect signature", async function () {
    const emailVerifierInputs = generateCircuitInputs({
      rsaSignature: dkimResult.signature,
      rsaPublicKey: dkimResult.publicKey,
      body: dkimResult.body,
      bodyHash: dkimResult.bodyHash,
      message: dkimResult.message,
      maxMessageLength: 640,
      maxBodyLength: 768,
    });


    expect.assertions(1);
    try {
      const witness = await circuit.calculateWitness({
        signature: emailVerifierInputs.signature,
        modulus: emailVerifierInputs.pubkey,
        base_message: ["1156466847851242602709362303526378171", "191372789510123109308037416804949834", "7204", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0"],
      });
      await circuit.checkConstraints(witness);
      await circuit.assertOut(witness, {})
    } catch (error) {
      expect((error as Error).message).toMatch("Assert Failed");
    }
  });
});
