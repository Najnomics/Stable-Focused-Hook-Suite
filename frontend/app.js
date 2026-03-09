const RuntimeAbi = [
  "function runtime(bytes32) view returns (bool,uint8,int24,uint32,int64,uint40,uint40,uint40,uint64)"
];

const ControllerAbi = [
  "function configurePoolPolicy((address,address,uint24,int24,address),(bool,int24,uint24,uint24,uint24,uint32,uint32,uint24,uint24,int64,int64,(uint24,uint128,uint24,uint32),(uint24,uint128,uint24,uint32),(uint24,uint128,uint24,uint32),(uint32,uint32,uint16,uint128)))"
];

const IncentivesAbi = [
  "function fundProgram(bytes32,uint256)",
  "function claimable(bytes32,address) view returns (uint256,uint256)",
  "function claim(bytes32,address) returns (uint256,uint256)"
];

const state = {
  provider: null,
  signer: null,
  account: null,
  hook: null,
  controller: null,
  incentives: null
};

const $ = (id) => document.getElementById(id);

function setStatus(text) {
  $("status").textContent = text;
}

function pretty(obj) {
  return JSON.stringify(obj, null, 2);
}

async function connect() {
  if (!window.ethereum) {
    setStatus("No injected wallet found");
    return;
  }

  state.provider = new ethers.BrowserProvider(window.ethereum);
  await state.provider.send("eth_requestAccounts", []);
  state.signer = await state.provider.getSigner();
  state.account = await state.signer.getAddress();

  $("claimTo").value = state.account;
  setStatus(`Wallet: ${state.account}`);
}

function loadContracts() {
  if (!state.signer) {
    throw new Error("Connect wallet first");
  }

  const hookAddress = $("hookAddress").value.trim();
  const controllerAddress = $("controllerAddress").value.trim();
  const incentivesAddress = $("incentivesAddress").value.trim();

  state.hook = new ethers.Contract(hookAddress, RuntimeAbi, state.signer);
  state.controller = new ethers.Contract(controllerAddress, ControllerAbi, state.signer);
  state.incentives = new ethers.Contract(incentivesAddress, IncentivesAbi, state.signer);

  setStatus(`Loaded suite for ${state.account}`);
}

async function refreshRuntime() {
  const poolId = $("poolId").value.trim();
  const out = $("runtimeOut");

  const runtime = await state.hook.runtime(poolId);
  const labels = [
    "initialized",
    "regime",
    "lastObservedTick",
    "smoothedVolatility",
    "flowSkew",
    "lastObservationTimestamp",
    "regimeSince",
    "lastHardSwapTimestamp",
    "lastSyncedPolicyNonce"
  ];

  const mapped = Object.fromEntries(labels.map((label, i) => [label, runtime[i].toString()]));
  out.textContent = pretty(mapped);
}

async function fundProgram() {
  const poolId = $("poolId").value.trim();
  const amount = $("fundAmount").value.trim();
  const tx = await state.incentives.fundProgram(poolId, amount);
  await tx.wait();
  $("incentivesOut").textContent = `fund tx: ${tx.hash}`;
}

async function queryClaimable() {
  const poolId = $("poolId").value.trim();
  const account = state.account;
  const result = await state.incentives.claimable(poolId, account);
  $("incentivesOut").textContent = pretty({
    claimable: result[0].toString(),
    penalty: result[1].toString()
  });
}

async function claim() {
  const poolId = $("poolId").value.trim();
  const to = $("claimTo").value.trim() || state.account;
  const tx = await state.incentives.claim(poolId, to);
  await tx.wait();
  $("incentivesOut").textContent = `claim tx: ${tx.hash}`;
}

async function configurePolicy() {
  const json = $("policyJson").value.trim();
  if (!json) {
    throw new Error("Policy JSON is empty");
  }

  const payload = JSON.parse(json);
  const tx = await state.controller.configurePoolPolicy(payload.poolKey, payload.policyInput);
  await tx.wait();
  $("policyOut").textContent = `policy tx: ${tx.hash}`;
}

function bind(id, fn) {
  $(id).addEventListener("click", async () => {
    try {
      await fn();
    } catch (error) {
      const message = error?.shortMessage || error?.message || String(error);
      if (id.includes("policy")) {
        $("policyOut").textContent = message;
      } else if (id.includes("claim") || id.includes("fund")) {
        $("incentivesOut").textContent = message;
      } else if (id.includes("regime")) {
        $("runtimeOut").textContent = message;
      } else {
        setStatus(message);
      }
    }
  });
}

bind("connectBtn", connect);
bind("loadBtn", loadContracts);
bind("regimeBtn", refreshRuntime);
bind("fundBtn", fundProgram);
bind("claimableBtn", queryClaimable);
bind("claimBtn", claim);
bind("policyBtn", configurePolicy);
