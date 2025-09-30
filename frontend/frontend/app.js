// AIPG Frontend: Recall and Generate NFT via ComfyUI (and optionally Grid API)
// Requirements: ethers.js v5 (loaded via CDN), pako.js for gzip inflate

// Contract Configuration - Current Base Sepolia Deployment
const CONTRACT_CONFIG = {
  GRID_NFT: '0xa87Eb64534086e914A4437ac75a1b554A10C9934',
  RECIPE_VAULT: '0x26FAd52658A726927De3331C5F5D01a5b09aC685', 
  MODEL_REGISTRY: '0xe660455D4A83bbbbcfDCF4219ad82447a831c8A1',
  RPC_URL: 'https://sepolia.base.org',
  CHAIN_ID: 84532,
  MINT_FEE: '0.025' // ETH
};

(function () {
  const $ = (id) => document.getElementById(id);

  // Normalize ComfyUI endpoint: if using local proxy on :8000, ensure "/comfy" path
  function normalizeComfyEndpoint(raw) {
    let url = (raw || '').trim();
    if (!url) return 'http://127.0.0.1:8188';
    try {
      const u = new URL(url);
      // If pointing to our frontend proxy on port 8000, route through /comfy
      if ((u.host.includes('localhost:8000') || u.host.includes('127.0.0.1:8000')) && !u.pathname.startsWith('/comfy')) {
        u.pathname = '/comfy' + (u.pathname.endsWith('/') ? '' : '') + u.pathname;
        // If u.pathname was '/', make it '/comfy'
        if (u.pathname === '/comfy/') u.pathname = '/comfy';
      }
      // Trim trailing slash
      u.pathname = u.pathname.replace(/\/$/, '');
      return u.toString();
    } catch {
      return url.replace(/\/$/, '');
    }
  }

  // UI elements
  const connectBtn = $("connect-wallet");
  const disconnectBtn = $("disconnect-wallet");
  const walletStatus = $("wallet-status");
  const walletAddress = $("wallet-address");
  const fetchBtn = $("fetch-nft");
  const statusMessages = $("status-messages");
  const nftSection = $("nft-section");
  const nftContent = $("nft-content");

  // Inputs
  const inputContract = $("contract-address");
  const inputTokenId = $("token-id");
  const inputRecipeVault = $("recipe-vault-address");
  const inputComfyEndpoint = $("comfyui-endpoint");
  const inputComfyClientId = $("comfyui-client-id");

  // GridNFT ABI - using actual contract functions
  const GRID_NFT_ABI = [
    // Public mappings (automatic getters)
    "function artworks(uint256 tokenId) view returns (tuple(uint256 modelId, uint256 recipeId, uint256 seed, uint16 steps, uint16 cfgTenths, uint16 width, uint16 height, uint8 tier, address worker, uint256 mintTimestamp, bool isReproducible))",
    "function artworkStrings(uint256 tokenId) view returns (tuple(string prompt, string negativePrompt, string sampler, string scheduler, string ipfsHash))",
    "function totalSupply() view returns (uint256)",
    "function ownerOf(uint256 tokenId) view returns (address)"
  ];

  const RECIPE_VAULT_ABI = [
    // getPublicRecipe(address nft, uint256 tokenId) → bytes
    {
      inputs: [
        { name: "nft", type: "address" },
        { name: "tokenId", type: "uint256" }
      ],
      name: "getPublicRecipe",
      outputs: [{ name: "data", type: "bytes" }],
      stateMutability: "view",
      type: "function"
    },
    // getRecipeMeta(address nft, uint256 tokenId) → (bytes32 recipeRoot, bytes32 dataHash, bool isPublic, uint8 compression, uint64 version, uint256 updatedAt)
    {
      inputs: [
        { name: "nft", type: "address" },
        { name: "tokenId", type: "uint256" }
      ],
      name: "getRecipeMeta",
      outputs: [
        { name: "recipeRoot", type: "bytes32" },
        { name: "dataHash", type: "bytes32" },
        { name: "isPublic", type: "bool" },
        { name: "compression", type: "uint8" },
        { name: "version", type: "uint64" },
        { name: "updatedAt", type: "uint256" }
      ],
      stateMutability: "view",
      type: "function"
    }
  ];

  // Utils
  function addStatus(msg, type = "info") {
    const div = document.createElement("div");
    div.className = `status ${type}`;
    div.textContent = msg;
    statusMessages.appendChild(div);
  }

  function clearStatus() {
    statusMessages.innerHTML = "";
  }

  function hexToBytes(hex) {
    const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
    const out = new Uint8Array(clean.length / 2);
    for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.substr(i * 2, 2), 16);
    return out;
  }

  function numOr(value, fallback) {
    const n = Number(value);
    return Number.isFinite(n) ? n : fallback;
  }

  function deriveSeedFromRenderRoot(renderRootHex) {
    // Deterministic: take low 32 bits of the renderRoot
    const clean = renderRootHex.startsWith("0x") ? renderRootHex.slice(2) : renderRootHex;
    // last 8 hex chars → uint32
    const last8 = clean.slice(-8);
    return parseInt(last8, 16) >>> 0; // unsigned 32-bit
  }

  function fillWorkflowPlaceholders(workflowObj, params) {
    // Simple approach: stringify, replace placeholders, parse back
    let s = JSON.stringify(workflowObj);
    const replacements = {
      "{{PROMPT}}": params.prompt,
      "{{NEGATIVE_PROMPT}}": params.negativePrompt || "",
      "{{SEED}}": String(params.seed),
      "{{STEPS}}": String(params.steps),
      "{{CFG}}": String(params.cfg),
      "{{SAMPLER}}": params.sampler,
      "{{SCHEDULER}}": params.scheduler,
      "{{WIDTH}}": String(params.width),
      "{{HEIGHT}}": String(params.height)
    };
    for (const [k, v] of Object.entries(replacements)) {
      s = s.split(k).join(v);
    }
    return JSON.parse(s);
  }

  async function fetchPublicRecipe(provider, recipeVaultAddr, gridNftAddr, tokenId) {
    const vault = new ethers.Contract(recipeVaultAddr, RECIPE_VAULT_ABI, provider);
    const meta = await vault.getRecipeMeta(gridNftAddr, tokenId);
    if (!meta.isPublic) throw new Error("Recipe is private; cannot fetch public bytes");
    const bytes = await vault.getPublicRecipe(gridNftAddr, tokenId);
    // bytes is a hex string (0x...), convert to Uint8Array and inflate
    const compressed = hexToBytes(bytes);
    const decompressed = window.pako.ungzip(compressed);
    const json = new TextDecoder().decode(decompressed);
    const recipe = JSON.parse(json);
    return { meta, recipe };
  }

  async function generateWithComfyUI(endpoint, clientId, workflow) {
    const payload = {
      prompt: workflow,
      client_id: clientId || "aipg-frontend"
    };
    // Submit prompt
    const submit = await fetch(`${endpoint.replace(/\/$/, "")}/prompt`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    if (!submit.ok) {
      throw new Error(`ComfyUI submit failed: ${submit.status} ${await submit.text()}`);
    }
    const res = await submit.json();
    const promptId = res.prompt_id || res.promptId || res["prompt_id"];
    if (!promptId) throw new Error("ComfyUI did not return prompt_id");

    // Poll history
    const start = Date.now();
    while (Date.now() - start < 120000) {
      await new Promise((r) => setTimeout(r, 2000));
      const h = await fetch(`${endpoint.replace(/\/$/, "")}/history/${promptId}`);
      if (!h.ok) continue;
      const hist = await h.json();
      const key = Object.keys(hist)[0];
      const item = hist[key];
      if (item && item.outputs) {
        // Look for SaveImage node outputs
        for (const nodeId of Object.keys(item.outputs)) {
          const out = item.outputs[nodeId];
          if (out.images && out.images.length) {
            const img = out.images[0];
            const imgUrl = `${endpoint.replace(/\/$/, "")}/view?filename=${encodeURIComponent(img.filename)}&subfolder=${encodeURIComponent(img.subfolder || "")}&type=${encodeURIComponent(img.type || "output")}`;
            return { imageUrl: imgUrl, filename: img.filename, subfolder: img.subfolder, type: img.type };
          }
        }
      }
    }
    throw new Error("ComfyUI generation timed out");
  }

  async function onFetchNFT() {
    clearStatus();
    try {
      const gridNftAddr = inputContract.value.trim();
      const tokenId = parseInt(inputTokenId.value, 10);
      const recipeVaultAddr = inputRecipeVault.value.trim();
      const comfyEndpoint = inputComfyEndpoint.value.trim();
      const comfyClientId = inputComfyClientId.value.trim() || "aipg-frontend";

      if (!ethers || !window.ethereum) throw new Error("MetaMask/ethers not available");
      const provider = new ethers.providers.Web3Provider(window.ethereum);
      const signer = provider.getSigner();
      await provider.send("eth_requestAccounts", []);

      addStatus("🔗 Connected. Fetching NFT data...", "info");
      
      // Create contract instance
      const grid = new ethers.Contract(gridNftAddr, GRID_NFT_ABI, provider);
      
      // Fetch real NFT data from contract
      const coreData = await grid.artworks(tokenId);
      const stringData = await grid.artworkStrings(tokenId);
      const owner = await grid.ownerOf(tokenId);
      
      // Use actual seed from contract data
      const seed = coreData.seed;

      addStatus(`✅ NFT loaded (token ${tokenId}) — Model: ${coreData.modelId}, Recipe: ${coreData.recipeId}`, "success");
      addStatus(`🧮 Seed: ${seed}, Steps: ${coreData.steps}, CFG: ${coreData.cfgTenths/10}`, "info");

      addStatus("📥 Fetching canonical workflow from RecipeVault...", "info");
      const { meta, recipe } = await fetchPublicRecipe(provider, recipeVaultAddr, gridNftAddr, tokenId);
      addStatus(`✅ Recipe loaded (version ${meta.version}, compression ${meta.compression})`, "success");

      // Use actual NFT parameters from contract
      const params = {
        prompt: stringData.prompt,
        negativePrompt: stringData.negativePrompt,
        seed: coreData.seed,
        steps: coreData.steps,
        cfg: coreData.cfgTenths / 10,
        sampler: stringData.sampler,
        scheduler: stringData.scheduler,
        width: coreData.width,
        height: coreData.height
      };

      // Fill placeholders in the recipe workflow
      const workflow = fillWorkflowPlaceholders(recipe, params);

      // Render UI summary
      nftSection.classList.remove("hidden");
      nftContent.innerHTML = `
        <div class="nft-display">
          <div class="nft-info">
            <h3>On-chain Data</h3>
            <p>Model ID: ${coreData.modelId}</p>
            <p>Recipe ID: ${coreData.recipeId}</p>
            <p>Seed: ${coreData.seed}</p>
            <p>Steps: ${coreData.steps}</p>
            <p>CFG Scale: ${coreData.cfgTenths/10}</p>
            <p>Dimensions: ${coreData.width}x${coreData.height}</p>
            <p>Worker: ${coreData.worker}</p>
            <p>Owner: ${owner}</p>
            <p>Tier: ${coreData.tier === 0 ? 'Standard' : 'Strict'}</p>
            <p>Prompt: ${stringData.prompt}</p>
            <p>Sampler: ${stringData.sampler}</p>
            <p>Scheduler: ${stringData.scheduler}</p>
          </div>
          <div class="image-preview" id="image-preview">
            <div class="status info">Ready to generate via ComfyUI</div>
          </div>
        </div>
        <div class="generation-controls">
          <button id="btn-generate-comfy" class="btn">Generate via ComfyUI</button>
        </div>
        <div class="recipe-display" style="margin-top:16px;">
          <h3>📝 Recipe Template</h3>
          <div class="recipe-info">
            <p><strong>RecipeVault meta:</strong> public=${meta.isPublic}, version=${meta.version}, updatedAt=${new Date(Number(meta.updatedAt) * 1000).toISOString()}</p>
          </div>
          <div class="recipe-json">${escapeHtml(JSON.stringify(recipe, null, 2))}</div>
          <button id="view-recipe-json" class="btn btn-small" style="margin-top:10px;">📄 View Full Recipe JSON</button>
        </div>
      `;

      // Attach generate button handler
      const genBtn = document.getElementById("btn-generate-comfy");
      const imagePreview = document.getElementById("image-preview");
      genBtn.onclick = async () => {
        try {
          genBtn.disabled = true;
          imagePreview.innerHTML = '<div class="status info"><span class="loading"></span> Submitting to ComfyUI...</div>';
          const result = await generateWithComfyUI(comfyEndpoint, comfyClientId, workflow);
          imagePreview.innerHTML = `<img src="${result.imageUrl}" alt="Generated" />`;
          addStatus("🎉 ComfyUI generation complete", "success");
        } catch (e) {
          console.error(e);
          imagePreview.innerHTML = `<div class="status error">${escapeHtml(e.message)}</div>`;
        } finally {
          genBtn.disabled = false;
        }
      };

    } catch (err) {
      console.error(err);
      addStatus(`❌ ${err.message || err}`, "error");
    }
  }

  function escapeHtml(s) {
    return s
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  // Wallet connect/disconnect
  connectBtn?.addEventListener("click", async () => {
    try {
      if (!window.ethereum) throw new Error("MetaMask not found");
      const provider = new ethers.providers.Web3Provider(window.ethereum);
      await provider.send("eth_requestAccounts", []);
      const signer = provider.getSigner();
      const addr = await signer.getAddress();
      walletAddress.textContent = addr;
      walletAddress.classList.remove("hidden");
      walletStatus.textContent = "Connected";
      walletStatus.className = "status success";
      connectBtn.classList.add("hidden");
      disconnectBtn.classList.remove("hidden");
      fetchBtn.disabled = false; // allow fetching without making the user retype
    } catch (e) {
      walletStatus.textContent = e.message || "Failed to connect";
      walletStatus.className = "status error";
    }
  });

  disconnectBtn?.addEventListener("click", async () => {
    walletAddress.textContent = "";
    walletAddress.classList.add("hidden");
    walletStatus.textContent = "Not connected";
    walletStatus.className = "status info";
    connectBtn.classList.remove("hidden");
    disconnectBtn.classList.add("hidden");
  });

  // Enable fetch button on load (handler is bound by AIPGNFTGenerator below)
  if (fetchBtn) {
    fetchBtn.disabled = false;
  }
})();

// AIPG AI Art NFT Generator Frontend
// Connects to MetaMask, fetches NFT data, and generates images via ComfyUI

class AIPGNFTGenerator {
    constructor() {
        this.provider = null;
        this.signer = null;
        this.account = null;
        this.gridNFTContract = null;
        this.recipeVaultContract = null;
        this.nftData = null;
        
        this.initializeEventListeners();
    }

    numOr(value, fallback) {
        const n = Number(value);
        return Number.isFinite(n) ? n : fallback;
    }

    initializeEventListeners() {
        document.getElementById('connect-wallet').addEventListener('click', () => this.connectWallet());
        document.getElementById('disconnect-wallet').addEventListener('click', () => this.disconnectWallet());
        document.getElementById('switch-network').addEventListener('click', () => this.switchToBaseSepolia());
        document.getElementById('fetch-nft').addEventListener('click', () => this.fetchNFTData());
        
        // Check if wallet is already connected
        this.checkWalletConnection();
    }

    async checkWalletConnection() {
        try {
            if (typeof window.ethereum === 'undefined') {
                return;
            }

            const accounts = await window.ethereum.request({ 
                method: 'eth_accounts' 
            });
            
            if (accounts && accounts.length > 0) {
                this.account = accounts[0];
                this.provider = new ethers.providers.Web3Provider(window.ethereum);
                this.signer = this.provider.getSigner();
                
                // Update UI
                document.getElementById('wallet-status').textContent = 'Connected';
                document.getElementById('wallet-status').className = 'status success';
                document.getElementById('wallet-address').textContent = this.account;
                document.getElementById('wallet-address').classList.remove('hidden');
                document.getElementById('connect-wallet').textContent = 'Connected';
                document.getElementById('connect-wallet').disabled = true;
                document.getElementById('disconnect-wallet').classList.remove('hidden');
                document.getElementById('fetch-nft').disabled = false;
                
                this.showStatus(`Already connected: ${this.account.substring(0, 6)}...${this.account.substring(38)}`, 'success');
            }
        } catch (error) {
            console.log('No wallet connected on page load');
        }
    }

    async switchToBaseSepolia() {
        try {
            await window.ethereum.request({
                method: 'wallet_switchEthereumChain',
                params: [{ chainId: '0x14a34' }], // Base Sepolia chain ID (84532)
            });
        } catch (switchError) {
            // This error code indicates that the chain has not been added to MetaMask
            if (switchError.code === 4902) {
                try {
                    await window.ethereum.request({
                        method: 'wallet_addEthereumChain',
                        params: [{
                            chainId: '0x14a34',
                            chainName: 'Base Sepolia',
                            nativeCurrency: {
                                name: 'ETH',
                                symbol: 'ETH',
                                decimals: 18
                            },
                            rpcUrls: ['https://sepolia.base.org'],
                            blockExplorerUrls: ['https://sepolia.basescan.org']
                        }]
                    });
                } catch (addError) {
                    throw new Error(`Failed to add Base Sepolia network: ${addError.message}`);
                }
            } else {
                throw new Error(`Failed to switch to Base Sepolia: ${switchError.message}`);
            }
        }
    }

    async connectWallet() {
        try {
            if (typeof window.ethereum === 'undefined') {
                this.showStatus('MetaMask not detected. Please install MetaMask.', 'error');
                return;
            }

            this.showStatus('Connecting to MetaMask...', 'info');
            
            // Request account access
            const accounts = await window.ethereum.request({ 
                method: 'eth_requestAccounts' 
            });
            
            if (!accounts || accounts.length === 0) {
                throw new Error('No accounts found');
            }
            
            this.account = accounts[0];
            console.log('Connected account:', this.account);
            
            // Create provider and signer
            this.provider = new ethers.providers.Web3Provider(window.ethereum);
            
            // Wait for provider to be ready
            await this.provider.ready;
            
            this.signer = this.provider.getSigner();
            
            // Verify the signer with better error handling
            try {
                const signerAddress = await this.signer.getAddress();
                console.log('Signer address:', signerAddress);
                console.log('Account address:', this.account);
                
                if (signerAddress.toLowerCase() !== this.account.toLowerCase()) {
                    console.warn('Signer address mismatch, retrying...');
                    // Retry getting the signer
                    this.signer = this.provider.getSigner();
                    const retryAddress = await this.signer.getAddress();
                    if (retryAddress.toLowerCase() !== this.account.toLowerCase()) {
                        throw new Error(`Signer address mismatch: ${retryAddress} vs ${this.account}`);
                    }
                }
            } catch (error) {
                console.error('Signer verification error:', error);
                // Try one more time with a fresh provider
                try {
                    console.log('Retrying with fresh provider...');
                    this.provider = new ethers.providers.Web3Provider(window.ethereum);
                    await this.provider.ready;
                    this.signer = this.provider.getSigner();
                    const finalAddress = await this.signer.getAddress();
                    if (finalAddress.toLowerCase() !== this.account.toLowerCase()) {
                        throw new Error(`Final signer verification failed: ${finalAddress} vs ${this.account}`);
                    }
                    console.log('Signer verification successful on retry');
                } catch (retryError) {
                    console.error('Final signer verification failed:', retryError);
                    console.warn('Proceeding without strict signer verification...');
                    // Continue without strict verification - sometimes MetaMask has timing issues
                }
            }
            
            // Update UI
            console.log('Updating UI elements...');
            const walletStatus = document.getElementById('wallet-status');
            const walletAddress = document.getElementById('wallet-address');
            const connectButton = document.getElementById('connect-wallet');
            const fetchButton = document.getElementById('fetch-nft');
            
            if (walletStatus) {
                walletStatus.textContent = 'Connected';
                walletStatus.className = 'status success';
                console.log('Updated wallet status');
            }
            
            if (walletAddress) {
                walletAddress.textContent = this.account;
                walletAddress.classList.remove('hidden');
                console.log('Updated wallet address');
            }
            
            if (connectButton) {
                connectButton.textContent = 'Connected';
                connectButton.disabled = true;
                console.log('Updated connect button');
            }
            
            const disconnectButton = document.getElementById('disconnect-wallet');
            if (disconnectButton) {
                disconnectButton.classList.remove('hidden');
                console.log('Showed disconnect button');
            }
            
            if (fetchButton) {
                fetchButton.disabled = false;
                console.log('Enabled fetch button');
            }
            
            this.showStatus(`Connected to MetaMask: ${this.account.substring(0, 6)}...${this.account.substring(38)}`, 'success');
            
            // Test the connection by getting network info
            try {
                // Force a network refresh by getting the chain ID directly from MetaMask
                const chainId = await window.ethereum.request({ method: 'eth_chainId' });
                const chainIdNumber = parseInt(chainId, 16);
                console.log('MetaMask chain ID (hex):', chainId);
                console.log('MetaMask chain ID (decimal):', chainIdNumber);
                
                const network = await this.provider.getNetwork();
                console.log('Provider network:', network);
                
                // Check both the provider network and MetaMask chain ID
                if (network.chainId === 84532n || chainIdNumber === 84532) {
                    this.showStatus(`Connected to Base Sepolia (Chain ID: ${chainIdNumber})`, 'success');
                    document.getElementById('switch-network').style.display = 'none';
                } else {
                    this.showStatus(`⚠️ WRONG NETWORK! Please switch to Base Sepolia (84532)`, 'error');
                    document.getElementById('switch-network').style.display = 'inline-block';
                }
            } catch (error) {
                console.log('Could not get network info:', error);
            }
            
            // Listen for account changes
            window.ethereum.on('accountsChanged', (accounts) => {
                if (accounts.length === 0) {
                    this.disconnectWallet();
                } else {
                    this.account = accounts[0];
                    document.getElementById('wallet-address').textContent = this.account;
                    this.showStatus(`Account changed: ${this.account.substring(0, 6)}...${this.account.substring(38)}`, 'info');
                }
            });
            
            // Listen for network changes
            window.ethereum.on('chainChanged', (chainId) => {
                console.log('Network changed to chain ID:', chainId);
                const chainIdNumber = parseInt(chainId, 16);
                console.log('New chain ID (decimal):', chainIdNumber);
                
                // Refresh the provider to match the new network
                this.provider = new ethers.providers.Web3Provider(window.ethereum);
                this.signer = this.provider.getSigner();
                console.log('Refreshed provider and signer for new network');
                
                if (chainIdNumber === 84532) {
                    this.showStatus(`✅ Switched to Base Sepolia (Chain ID: ${chainIdNumber})`, 'success');
                    document.getElementById('switch-network').style.display = 'none';
                } else {
                    this.showStatus(`⚠️ Wrong network! Please switch to Base Sepolia (84532)`, 'error');
                    document.getElementById('switch-network').style.display = 'inline-block';
                }
            });
            
        } catch (error) {
            console.error('Wallet connection error:', error);
            this.showStatus(`Failed to connect wallet: ${error.message}`, 'error');
        }
    }

    disconnectWallet() {
        this.account = null;
        this.provider = null;
        this.signer = null;
        
        document.getElementById('wallet-status').textContent = 'Not connected';
        document.getElementById('wallet-status').className = 'status info';
        document.getElementById('wallet-address').textContent = '';
        document.getElementById('wallet-address').classList.add('hidden');
        document.getElementById('connect-wallet').textContent = 'Connect MetaMask';
        document.getElementById('connect-wallet').disabled = false;
        document.getElementById('disconnect-wallet').classList.add('hidden');
        document.getElementById('fetch-nft').disabled = true;
        
        this.showStatus('Wallet disconnected', 'info');
    }

    addNetworkSwitchButton() {
        const walletSection = document.querySelector('.wallet-section');
        if (walletSection && !document.getElementById('switch-network-btn')) {
            const switchBtn = document.createElement('button');
            switchBtn.id = 'switch-network-btn';
            switchBtn.className = 'btn btn-secondary';
            switchBtn.textContent = 'Switch to Base Sepolia';
            switchBtn.onclick = () => this.switchToBaseSepolia();
            walletSection.appendChild(switchBtn);
        }
    }

    async switchToBaseSepolia() {
        try {
            await window.ethereum.request({
                method: 'wallet_switchEthereumChain',
                params: [{ chainId: '0x14a34' }], // Base Sepolia chain ID
            });
        } catch (switchError) {
            // If the network doesn't exist, add it
            if (switchError.code === 4902) {
                try {
                    await window.ethereum.request({
                        method: 'wallet_addEthereumChain',
                        params: [{
                            chainId: '0x14a34',
                            chainName: 'Base Sepolia',
                            rpcUrls: ['https://sepolia.base.org'],
                            nativeCurrency: {
                                name: 'Ethereum',
                                symbol: 'ETH',
                                decimals: 18,
                            },
                            blockExplorerUrls: ['https://sepolia.basescan.org'],
                        }],
                    });
                } catch (addError) {
                    this.showStatus(`Failed to add Base Sepolia network: ${addError.message}`, 'error');
                }
            } else {
                this.showStatus(`Failed to switch network: ${switchError.message}`, 'error');
            }
        }
    }

    showNetworkError() {
        const errorDiv = document.createElement('div');
        errorDiv.id = 'network-error';
        errorDiv.className = 'network-error';
        errorDiv.innerHTML = `
            <h3>🚨 Wrong Network Detected!</h3>
            <p>You are connected to the wrong network. This app requires <strong>Base Sepolia Testnet</strong>.</p>
            <p>Please switch your MetaMask to Base Sepolia (Chain ID: 84532) to continue.</p>
            <button onclick="this.parentElement.remove()" class="btn">Got it</button>
        `;
        
        // Add some CSS for the error
        errorDiv.style.cssText = `
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: #ff4444;
            color: white;
            padding: 20px;
            border-radius: 10px;
            z-index: 1000;
            text-align: center;
            box-shadow: 0 4px 20px rgba(0,0,0,0.5);
        `;
        
        document.body.appendChild(errorDiv);
    }

    async refreshProvider() {
        try {
            console.log('Refreshing provider...');
            this.provider = new ethers.providers.Web3Provider(window.ethereum);
            await this.provider.ready;
            this.signer = this.provider.getSigner();
            console.log('Provider refreshed successfully');
        } catch (error) {
            console.error('Failed to refresh provider:', error);
            throw error;
        }
    }

    async fetchNFTData() {
        try {
            // Check and switch network first
            const currentChainId = await window.ethereum.request({ method: 'eth_chainId' });
            const currentChainIdNumber = parseInt(currentChainId, 16);
            if (currentChainIdNumber !== 84532) {
                this.showStatus('Switching to Base Sepolia...', 'info');
                await this.switchToBaseSepolia();
                // After switching, get new provider
                this.provider = new ethers.providers.Web3Provider(window.ethereum);
                await this.provider.ready;
                this.signer = this.provider.getSigner();
            }
            
            // Refresh provider to ensure network sync
            await this.refreshProvider();
            
            const contractAddress = document.getElementById('contract-address').value;
            const tokenIdInput = document.getElementById('token-id').value;
            const tokenId = ethers.BigNumber.from(tokenIdInput);
            const recipeVaultAddress = document.getElementById('recipe-vault-address').value;
            
            if (!contractAddress || !tokenId || !recipeVaultAddress) {
                this.showStatus('Please fill in all contract addresses and token ID', 'error');
                return;
            }

            this.showStatus('Fetching NFT data from blockchain...', 'info');
            
            // GridNFT Contract ABI (NEW complete structure)
            const gridNFTABI = [
                "function getCompleteArtwork(uint256 tokenId) view returns (tuple(uint256 modelId, uint256 recipeId, uint256 seed, uint16 steps, uint16 cfgTenths, uint16 width, uint16 height, uint8 tier, address worker, uint256 mintTimestamp, bool isReproducible), tuple(string prompt, string negativePrompt, string sampler, string scheduler, string ipfsHash))",
                "function tokenURI(uint256 tokenId) view returns (string)",
                "function ownerOf(uint256 tokenId) view returns (address)"
            ];
            
            // RecipeVault Contract ABI (simplified)
            const recipeVaultABI = [
                "function getPublicRecipe(address nft, uint256 tokenId) view returns (bytes memory)",
                "function getRecipeMeta(address nft, uint256 tokenId) view returns (tuple(bytes32 recipeRoot, bytes32 dataHash, bool isPublic, uint8 compression, uint64 version, uint256 updatedAt))"
            ];
            
            // Create contract instances
            this.gridNFTContract = new ethers.Contract(contractAddress, gridNFTABI, this.signer);
            this.recipeVaultContract = new ethers.Contract(recipeVaultAddress, recipeVaultABI, this.signer);
            
            // Check network first - get chain ID directly from MetaMask
            const chainId = await window.ethereum.request({ method: 'eth_chainId' });
            const chainIdNumber = parseInt(chainId, 16);
            console.log('MetaMask chain ID (hex):', chainId);
            console.log('MetaMask chain ID (decimal):', chainIdNumber);
            
            const network = await this.provider.getNetwork();
            console.log('Provider network:', network);
            
            if (chainIdNumber !== 84532) {
                throw new Error(`Wrong network! Please switch to Base Sepolia (Chain ID: 84532). Current MetaMask: ${chainIdNumber}, Provider: ${network.chainId}`);
            }
            
            // Test basic contract connection first
            try {
                const code = await this.provider.getCode(contractAddress);
                console.log('Contract code length:', code.length);
                if (code === '0x') {
                    throw new Error(`Contract not found at address ${contractAddress} on Base Sepolia`);
                }
            } catch (error) {
                throw new Error(`Contract connection failed: ${error.message}`);
            }
            
            // Fetch NFT data
            console.log('Attempting to fetch artwork for token:', tokenId);
            console.log('Contract address:', contractAddress);
            console.log('Network:', await this.provider.getNetwork());
            
            // Fetch combined artwork data (single canonical path)
            const [coreData, stringData] = await this.gridNFTContract.getCompleteArtwork(tokenId);
            const owner = await this.gridNFTContract.ownerOf(tokenId);
            console.log('✅ Successfully fetched NFT data via getCompleteArtwork');
            
            console.log('Core artwork data:', coreData);
            console.log('String artwork data:', stringData);
            console.log('Owner:', owner);
            
            this.nftData = {
                tokenId: tokenId,
                modelId: coreData.modelId,
                recipeId: coreData.recipeId,
                seed: coreData.seed,
                steps: coreData.steps,
                cfgTenths: coreData.cfgTenths,
                width: coreData.width,
                height: coreData.height,
                tier: coreData.tier,
                worker: coreData.worker,
                timestamp: coreData.mintTimestamp,
                isReproducible: coreData.isReproducible,
                prompt: stringData.prompt,
                negativePrompt: stringData.negativePrompt,
                sampler: stringData.sampler,
                scheduler: stringData.scheduler,
                ipfsHash: stringData.ipfsHash,
                owner: owner
            };
            
            // Fetch recipe template
            this.showStatus('Fetching recipe template...', 'info');
            console.log('NFT address:', contractAddress);
            console.log('Token ID:', tokenId);
            console.log('RecipeVault address:', recipeVaultAddress);
            
            let recipeMeta;
            try {
                // First get the metadata to check if it's public
                recipeMeta = await this.recipeVaultContract.getRecipeMeta(contractAddress, tokenId);
                console.log('Recipe meta:', recipeMeta);
                
                if (recipeMeta && recipeMeta.isPublic) {
                    // Only try to get public recipe if metadata says it's public
                    const recipeData = await this.recipeVaultContract.getPublicRecipe(contractAddress, tokenId);
                    console.log('Public recipe data received (hex length):', recipeData.length);
                    
                    // Decode on-chain bytes based on compression flag
                    let recipeJson;
                    if (typeof recipeData === 'string' && recipeData.startsWith('0x')) {
                        const hex = recipeData.slice(2);
                        const byteArray = new Uint8Array(hex.match(/.{1,2}/g).map(byte => parseInt(byte, 16)));
                        const compression = recipeMeta && (typeof recipeMeta.compression !== 'undefined')
                            ? Number(recipeMeta.compression)
                            : 1; // default assume gzip if unknown
                        let utf8Bytes;
                        if (compression === 1) {
                            // Gzip
                            utf8Bytes = window.pako.ungzip(byteArray);
                        } else {
                            // None
                            utf8Bytes = byteArray;
                        }
                        const decoder = new TextDecoder('utf-8');
                        const jsonStr = decoder.decode(utf8Bytes);
                        this.nftData.recipeTemplate = JSON.parse(jsonStr);
                    }
                } else {
                    // Recipe is private, use default template
                    console.log('Recipe is private, using default template');
                    this.nftData.recipeTemplate = {
                        workflowHash: this.nftData.recipeRoot,
                        renderRoot: this.nftData.renderRoot,
                        samplerType: 'euler',
                        schedulerType: 'simple',
                        mode: 'Strict',
                        precision: 'fp32',
                        note: 'Private recipe - using default template with on-chain roots'
                    };
                }
            }
            catch (error) {
                console.error('Error fetching recipe:', error);
                // Use default template if anything fails
                this.nftData.recipeTemplate = {
                    workflowHash: this.nftData.recipeRoot,
                    renderRoot: this.nftData.renderRoot,
                    samplerType: 'euler',
                    schedulerType: 'simple',
                    mode: 'Strict',
                    precision: 'fp32',
                    note: 'Error fetching recipe - using default template with on-chain roots'
                };
            }
            
            // Display NFT data
            this.displayNFTData();
            
            this.showStatus('NFT data fetched successfully!', 'success');
            
        } catch (error) {
            this.showStatus(`Failed to fetch NFT data: ${error.message}`, 'error');
            console.error('Error fetching NFT data:', error);
        }
    }

    displayNFTData() {
        const nftSection = document.getElementById('nft-section');
        const nftContent = document.getElementById('nft-content');
        
        nftSection.classList.remove('hidden');
        
        nftContent.innerHTML = `
            <div class="nft-display">
                <div class="nft-info">
                    <h3>NFT Information</h3>
                    <p><span class="label">Token ID:</span><span class="value">${this.nftData.tokenId}</span></p>
                    <p><span class="label">Model ID:</span><span class="value">${this.nftData.modelId}</span></p>
                    <p><span class="label">Recipe ID:</span><span class="value">${this.nftData.recipeId}</span></p>
                    <p><span class="label">Seed:</span><span class="value">${this.nftData.seed}</span></p>
                    <p><span class="label">Steps:</span><span class="value">${this.nftData.steps}</span></p>
                    <p><span class="label">CFG Scale:</span><span class="value">${this.nftData.cfgTenths / 10}</span></p>
                    <p><span class="label">Dimensions:</span><span class="value">${this.nftData.width}x${this.nftData.height}</span></p>
                    <p><span class="label">Sampler:</span><span class="value">${this.nftData.sampler}</span></p>
                    <p><span class="label">Scheduler:</span><span class="value">${this.nftData.scheduler}</span></p>
                    <p><span class="label">Worker:</span><span class="value">${this.nftData.worker}</span></p>
                    <p><span class="label">Owner:</span><span class="value">${this.nftData.owner}</span></p>
                    <p><span class="label">Tier:</span><span class="value">${this.nftData.tier === 0 ? 'Standard' : 'Strict'}</span></p>
                    <p><span class="label">Timestamp:</span><span class="value">${new Date(this.nftData.timestamp * 1000).toLocaleString()}</span></p>
                    <p><span class="label">IPFS Hash:</span><span class="value">${this.nftData.ipfsHash || 'N/A'}</span></p>
                </div>
                
                <div class="prompt-display">
                    <h3>Prompt Information</h3>
                    <div class="prompt-info">
                        <p><span class="label">Prompt:</span></p>
                        <div class="prompt-text">${this.nftData.prompt || 'N/A'}</div>
                        <p><span class="label">Negative Prompt:</span></p>
                        <div class="prompt-text">${this.nftData.negativePrompt || 'N/A'}</div>
                    </div>
                </div>
                
                <div class="recipe-display">
                    <h3>Recipe Template</h3>
                    <div class="recipe-info">
                        <p><span class="label">Recipe ID:</span><span class="value">${this.nftData.recipeId}</span></p>
                        <p><span class="label">Sampler:</span><span class="value">${this.nftData.sampler}</span></p>
                        <p><span class="label">Scheduler:</span><span class="value">${this.nftData.scheduler}</span></p>
                        ${this.nftData.recipeTemplate?.note ? `<p><em>${this.nftData.recipeTemplate.note}</em></p>` : ''}
                    </div>
                    <button id="view-recipe-json" class="btn btn-small">View Full Recipe JSON</button>
                </div>
                
                <div class="image-preview">
                    <h3>Generated Image</h3>
                    <div id="generated-image-container">
                        <p>Click "Generate Image" to create the artwork</p>
                    </div>
                </div>
            </div>
            
            <div class="generation-controls">
                <button id="generate-image" class="btn">Generate Image</button>
                <button id="download-image" class="btn btn-secondary" disabled>Download Image</button>
                <button id="view-workflow" class="btn btn-secondary">View Workflow</button>
            </div>
            
            <div id="workflow-json" class="workflow-json hidden">
                <pre id="workflow-content"></pre>
            </div>
            
            <div id="recipe-json" class="recipe-json hidden">
                <h4>Full Recipe Template JSON</h4>
                <pre id="recipe-content"></pre>
            </div>
        `;
        
        // Add event listeners for new buttons
        document.getElementById('generate-image').addEventListener('click', () => this.generateImage());
        document.getElementById('download-image').addEventListener('click', () => this.downloadImage());
        document.getElementById('view-workflow').addEventListener('click', () => this.toggleWorkflow());
        document.getElementById('view-recipe-json').addEventListener('click', () => this.toggleRecipeJson());
    }

    async generateImage() {
        const generateBtn = document.getElementById('generate-image');
        const imagePreview = document.getElementById('generated-image-container');
        
        try {
            // Disable button and show loading
            generateBtn.disabled = true;
            generateBtn.textContent = 'Generating...';
            imagePreview.innerHTML = '<div class="status info"><span class="loading"></span> Generating image with ComfyUI...</div>';
            
            this.showStatus('Generating image with ComfyUI...', 'info');
            
            const comfyUIEndpoint = document.getElementById('comfyui-endpoint').value;
            const clientId = document.getElementById('comfyui-client-id').value || 'aipg-frontend';
            
            if (!comfyUIEndpoint) {
                throw new Error('ComfyUI endpoint not configured');
            }
            
            // Create parameters from the recipe template
            const params = this.createGenerationParams();
            
            // Create ComfyUI workflow based on the recipe template
            const workflow = this.createComfyUIWorkflow(params);
            
            // Submit the workflow to ComfyUI
            console.log('Sending workflow to ComfyUI:', workflow);
            const response = await fetch(`${comfyUIEndpoint}/prompt`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Client-Agent': 'AIPG-Frontend/1.0'
                },
                body: JSON.stringify({
                    prompt: workflow,
                    client_id: clientId
                })
            });
            
            if (!response.ok) {
                const errorText = await response.text();
                console.error('ComfyUI error response:', errorText);
                throw new Error(`ComfyUI request failed: ${response.status} ${response.statusText} - ${errorText}`);
            }
            
            const data = await response.json();
            const promptId = data.prompt_id;
            
            console.log('ComfyUI job submitted with ID:', promptId);
            imagePreview.innerHTML = '<div class="status info"><span class="loading"></span> ComfyUI job submitted. Waiting for completion...</div>';
            this.showStatus(`ComfyUI job submitted with ID: ${promptId}. Waiting for completion...`, 'info');
            
            // Poll for completion
            await this.pollForComfyUICompletion(comfyUIEndpoint, promptId);
            
        } catch (error) {
            console.error('ComfyUI generation failed:', error);
            this.showStatus(`Image generation failed: ${error.message}`, 'error');
            imagePreview.innerHTML = `<div class="status error">Generation failed: ${error.message}</div>`;
        } finally {
            // Re-enable button
            generateBtn.disabled = false;
            generateBtn.textContent = 'Generate Image';
        }
    }

    createGenerationParams() {
        // Use NFT data directly for generation parameters
        if (!this.nftData) {
            throw new Error('No NFT data available');
        }
        
        // Use exact parameters from the NFT
        let params = {
            prompt: this.nftData.prompt || "a beautiful Nordic woman",
            negative_prompt: this.nftData.negativePrompt || "",
            model: "flux.1-krea-dev",
            width: this.nftData.width || 1024,
            height: this.nftData.height || 1024,
            steps: this.nftData.steps || 29,
            cfg_scale: this.nftData.cfgTenths ? this.nftData.cfgTenths / 10 : 4,
            sampler_name: this.nftData.sampler || "euler",
            scheduler: this.nftData.scheduler || "simple",
            seed: this.nftData.seed || Math.floor(Math.random() * 1000000000)
        };
        
        console.log('Generated params from NFT data:', params);
        
        // Extract parameters from the actual recipe template (if available)
        const template = this.nftData.recipeTemplate;
        if (template) {
            console.log('Extracting parameters from recipe template:', template);
            
            // Look for workflow template data
            if (template.template) {
                Object.keys(template.template).forEach(nodeId => {
                    const node = template.template[nodeId];
                    
                    // Extract from KSampler node
                    if (node.class_type === 'KSampler') {
                        if (node.inputs.steps) params.steps = node.inputs.steps;
                        if (node.inputs.cfg) params.cfg_scale = node.inputs.cfg;
                        if (node.inputs.sampler_name) params.sampler_name = node.inputs.sampler_name;
                        if (node.inputs.scheduler) params.scheduler = node.inputs.scheduler;
                        if (node.inputs.seed) params.seed = node.inputs.seed;
                    }
                    
                    // Extract prompts from CLIPTextEncode nodes
                    if (node.class_type === 'CLIPTextEncode' && node.inputs && node.inputs.text) {
                        let text = node.inputs.text;
                        
                        // Substitute placeholders with NFT data if available
                        if (this.nftData) {
                            text = text.replace(/\{\{PROMPT\}\}/g, this.nftData.prompt || '');
                            text = text.replace(/\{\{NEGATIVE_PROMPT\}\}/g, this.nftData.negativePrompt || '');
                            text = text.replace(/\{\{SEED\}\}/g, this.nftData.seed || '');
                            text = text.replace(/\{\{STEPS\}\}/g, this.nftData.steps || '29');
                            text = text.replace(/\{\{CFG\}\}/g, (this.nftData.cfgTenths ? this.nftData.cfgTenths / 10 : '4'));
                            text = text.replace(/\{\{SAMPLER\}\}/g, this.nftData.sampler || 'euler');
                            text = text.replace(/\{\{SCHEDULER\}\}/g, this.nftData.scheduler || 'simple');
                        }
                        
                        // Try to identify positive vs negative prompts
                        if (node._meta && node._meta.title) {
                            const title = node._meta.title.toLowerCase();
                            if (title.includes('positive') || title.includes('prompt')) {
                                params.prompt = text;
                            } else if (title.includes('negative')) {
                                params.negative_prompt = text;
                            }
                        } else {
                            // If no metadata, check the text content
                            if (text.includes('NEGATIVE') || text.toLowerCase().includes('negative')) {
                                params.negative_prompt = text;
                            } else {
                                params.prompt = text;
                            }
                        }
                    }
                    
                    // Extract image dimensions from LoadImage or other nodes
                    if (node.class_type === 'LoadImage' && node.inputs && node.inputs.image) {
                        // This might contain dimension info
                    }
                });
            }
            
            // Check for direct parameter overrides in template
            if (template.samplerType) params.sampler_name = template.samplerType;
            if (template.schedulerType) params.scheduler = template.schedulerType;
            if (template.mode) {
                // Map mode to appropriate settings
                if (template.mode === 'Strict') {
                    params.cfg_scale = 4; // Higher CFG for strict mode
                }
            }
            if (template.precision) {
                // Map precision to appropriate settings
                if (template.precision === 'fp32') {
                    // Use higher quality settings
                    params.steps = Math.max(params.steps, 29);
                }
            }
        }
        
        // Coerce numeric fields and apply fallbacks
        params.steps = this.numOr(params.steps, 29);
        params.cfg_scale = this.numOr(params.cfg_scale, 4);
        params.width = this.numOr(params.width, 1024);
        params.height = this.numOr(params.height, 1024);
        params.seed = Math.floor(this.numOr(params.seed, Math.random() * 1000000000));

        // NFT already has the exact seed stored, no need for renderRoot conversion
        // The seed is already set from this.nftData.seed above
        
        console.log('Final generation parameters:', params);
        return params;
    }

    createComfyUIWorkflow(params) {
        // Create a ComfyUI workflow based on the parameters
        const workflow = {
            "1": {
                "inputs": {
                    "text": params.prompt,
                    "clip": ["4", 1]
                },
                "class_type": "CLIPTextEncode",
                "_meta": {
                    "title": "CLIP Text Encode (Prompt)"
                }
            },
            "2": {
                "inputs": {
                    "text": params.negative_prompt || "blurry, low quality, deformed, watermark, text, jpeg artifacts",
                    "clip": ["4", 1]
                },
                "class_type": "CLIPTextEncode",
                "_meta": {
                    "title": "CLIP Text Encode (Negative)"
                }
            },
            "3": {
                "inputs": {
                    "seed": params.seed,
                    "steps": params.steps,
                    "cfg": params.cfg_scale,
                    "sampler_name": params.sampler_name,
                    "scheduler": params.scheduler,
                    "denoise": 1,
                    "model": ["4", 0],
                    "positive": ["1", 0],
                    "negative": ["2", 0],
                    "latent_image": ["5", 0]
                },
                "class_type": "KSampler",
                "_meta": {
                    "title": "KSampler"
                }
            },
            "4": {
                "inputs": {
                    "ckpt_name": "flux1-dev-fp8-comfyorg.safetensors"
                },
                "class_type": "CheckpointLoaderSimple",
                "_meta": {
                    "title": "Load Checkpoint"
                }
            },
            "5": {
                "inputs": {
                    "width": params.width,
                    "height": params.height,
                    "batch_size": 1
                },
                "class_type": "EmptyLatentImage",
                "_meta": {
                    "title": "Empty Latent Image"
                }
            },
            "6": {
                "inputs": {
                    "samples": ["3", 0],
                    "vae": ["4", 2]
                },
                "class_type": "VAEDecode",
                "_meta": {
                    "title": "VAE Decode"
                }
            },
            "7": {
                "inputs": {
                    "filename_prefix": "aipg_nft",
                    "images": ["6", 0]
                },
                "class_type": "SaveImage",
                "_meta": {
                    "title": "Save Image"
                }
            }
        };
        
        return workflow;
    }

    async pollForComfyUICompletion(endpoint, promptId) {
        const maxAttempts = 60; // 5 minutes max
        let attempts = 0;
        
        console.log(`Starting to poll for completion of prompt: ${promptId}`);
        
        const poll = async () => {
            try {
                console.log(`Polling attempt ${attempts + 1}/${maxAttempts} for prompt: ${promptId}`);
                const response = await fetch(`${endpoint}/history/${promptId}`);
                
                if (!response.ok) {
                    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                }
                
                const data = await response.json();
                console.log('Polling response:', data);
                
                if (data[promptId]) {
                    const promptData = data[promptId];
                    console.log('Prompt data:', promptData);
                    
                    // Check if we have outputs (image generated)
                    if (promptData.outputs) {
                        console.log('Found outputs:', promptData.outputs);
                        
                        // Find the image node
                        const imageNodeId = Object.keys(promptData.outputs).find(id => 
                            promptData.outputs[id].images && promptData.outputs[id].images.length > 0
                        );
                        
                        if (imageNodeId) {
                            const imageData = promptData.outputs[imageNodeId].images[0];
                            console.log('Found image data:', imageData);
                            
                            const imageUrl = `${endpoint}/view?filename=${imageData.filename}&subfolder=${imageData.subfolder || ''}&type=${imageData.type || 'output'}`;
                            console.log('Image URL:', imageUrl);
                            
                            this.displayGeneratedImage(imageUrl);
                            this.showStatus('Image generated successfully!', 'success');
                            document.getElementById('download-image').disabled = false;
                            return;
                        }
                    }
                    
                    // Check status
                    if (promptData.status) {
                        const status = promptData.status;
                        console.log('Status:', status);
                        
                        if (status.status_str === 'success') {
                            console.log('Generation completed successfully');
                            // Continue polling to get the outputs
                        } else if (status.status_str === 'error') {
                            throw new Error(`Generation failed: ${status.status_str}`);
                        }
                    }
                }
                
                attempts++;
                if (attempts < maxAttempts) {
                    console.log(`Continuing to poll in 3 seconds... (${attempts}/${maxAttempts})`);
                    setTimeout(poll, 3000); // Poll every 3 seconds
                } else {
                    throw new Error('Generation timeout - no image generated after 3 minutes');
                }
                
            } catch (error) {
                console.error('Polling error:', error);
                this.showStatus(`Polling error: ${error.message}`, 'error');
            }
        };
        
        poll();
    }

    async pollForAIPGCompletion(jobId) {
        const maxAttempts = 30; // 5 minutes max
        let attempts = 0;
        
        const poll = async () => {
            try {
                const response = await fetch(`https://api.aipowergrid.io/api/v2/generate/status/${jobId}`, {
                    headers: {
                        'apikey': 'SRjE7PuHTW1SG4rd_AqYGg'
                    }
                });
                
                if (response.status === 429) {
                    this.showStatus('Rate limited, waiting longer...', 'warning');
                    attempts++;
                    if (attempts < maxAttempts) {
                        setTimeout(poll, 15000); // Wait 15 seconds on rate limit
                    } else {
                        throw new Error('Generation timeout due to rate limiting');
                    }
                    return;
                }
                
                if (!response.ok) {
                    throw new Error(`API error: ${response.status} ${response.statusText}`);
                }
                
                const data = await response.json();
                
                if (data.done) {
                    if (data.generations && data.generations.length > 0) {
                        const generation = data.generations[0];
                        
                        this.displayGeneratedImage(generation.img);
                        this.showStatus('Image generated successfully!', 'success');
                        document.getElementById('download-image').disabled = false;
                        return;
                    } else {
                        throw new Error('No generations found in completed job');
                    }
                } else if (data.faulted) {
                    throw new Error('Generation failed');
                }
                
                attempts++;
                if (attempts < maxAttempts) {
                    setTimeout(poll, 10000); // Poll every 10 seconds to avoid rate limits
                } else {
                    throw new Error('Generation timeout');
                }
                
            } catch (error) {
                this.showStatus(`Polling error: ${error.message}`, 'error');
            }
        };
        
        poll();
    }



    displayGeneratedImage(imageUrl) {
        const container = document.getElementById('generated-image-container');
        container.innerHTML = `
            <img src="${imageUrl}" alt="Generated AI Art" style="max-width: 100%; border-radius: 10px; box-shadow: 0 5px 15px rgba(0,0,0,0.2);">
            <p style="margin-top: 10px; font-size: 14px; color: #666;">Generated from blockchain recipe</p>
        `;
        
        // Store image URL for download
        this.generatedImageUrl = imageUrl;
    }

    downloadImage() {
        if (this.generatedImageUrl) {
            const link = document.createElement('a');
            link.href = this.generatedImageUrl;
            link.download = `aipg-nft-${this.nftData.tokenId}-generated.png`;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        }
    }

    toggleWorkflow() {
        const workflowDiv = document.getElementById('workflow-json');
        const workflowContent = document.getElementById('workflow-content');
        
        if (workflowDiv.classList.contains('hidden')) {
            workflowContent.textContent = JSON.stringify(this.nftData.recipeTemplate, null, 2);
            workflowDiv.classList.remove('hidden');
        } else {
            workflowDiv.classList.add('hidden');
        }
    }

    toggleRecipeJson() {
        const recipeDiv = document.getElementById('recipe-json');
        const recipeContent = document.getElementById('recipe-content');
        
        if (recipeDiv.classList.contains('hidden')) {
            recipeContent.textContent = JSON.stringify(this.nftData.recipeTemplate, null, 2);
            recipeDiv.classList.remove('hidden');
        } else {
            recipeDiv.classList.add('hidden');
        }
    }

    showStatus(message, type) {
        const statusDiv = document.getElementById('status-messages');
        const statusElement = document.createElement('div');
        statusElement.className = `status ${type}`;
        statusElement.innerHTML = `
            <span class="loading"></span> ${message}
        `;
        
        statusDiv.appendChild(statusElement);
        
        // Remove after 5 seconds
        setTimeout(() => {
            if (statusElement.parentNode) {
                statusElement.parentNode.removeChild(statusElement);
            }
        }, 5000);
    }
}

// Initialize the app when DOM is loaded and ethers is available
function initializeApp() {
    if (typeof ethers === 'undefined') {
        console.error('Ethers.js not available, retrying in 1 second...');
        setTimeout(initializeApp, 1000);
        return;
    }
    
    console.log('Initializing AIPG NFT Generator...');
    new AIPGNFTGenerator();
}

// Wait for both DOM and ethers to be ready
document.addEventListener('DOMContentLoaded', initializeApp);
