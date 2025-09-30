# AIPG AI Art NFT Generator Frontend

An interactive web frontend that allows users to connect their MetaMask wallet, fetch NFT data from the blockchain, and regenerate AI art using their own ComfyUI endpoint.

## Features

- 🔗 **MetaMask Integration**: Connect wallet and interact with Base Sepolia
- 🖼️ **NFT Data Fetching**: Pull artwork data from GridNFT contract
- 📋 **Recipe Retrieval**: Fetch recipe templates from RecipeVault
- 🎨 **ComfyUI Generation**: Generate images using your local ComfyUI server
- 💾 **Image Download**: Download generated images
- 🔍 **Workflow Inspection**: View the complete ComfyUI workflow JSON

## Setup

1. **Install a local web server** (required for MetaMask integration):
   ```bash
   # Using Python
   python -m http.server 8000
   
   # Using Node.js
   npx serve .
   
   # Using PHP
   php -S localhost:8000
   ```

2. **Open in browser**: Navigate to `http://localhost:8000`

3. **Install MetaMask**: Make sure you have MetaMask installed and connected to Base Sepolia

## Usage

1. **Connect Wallet**: Click "Connect MetaMask" and approve the connection
2. **Enter Contract Addresses**: 
   - GridNFT Contract: `0x2cE108c0EE26f3dF27F26E0544037B79b1c395f7`
   - RecipeVault Contract: `0x8B8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c`
3. **Enter Token ID**: Use `3` for the dragon NFT we tested
4. **Configure ComfyUI**: Enter your ComfyUI endpoint (default: `http://172.30.30.122:8188`)
5. **Fetch NFT Data**: Click "Fetch NFT Data" to pull information from blockchain
6. **Generate Image**: Click "Generate Image" to create the artwork using ComfyUI

## Contract Addresses (Base Sepolia)

- **GridNFT**: `0x2cE108c0EE26f3dF27F26E0544037B79b1c395f7`
- **RecipeVault**: `0x8B8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c`
- **ModelShop**: `0x8B8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c`

## How It Works

1. **Blockchain Data Retrieval**:
   - Fetches artwork data from GridNFT contract
   - Retrieves recipe template from RecipeVault
   - Parses recipe JSON for ComfyUI workflow

2. **Image Generation**:
   - Creates complete ComfyUI workflow from template
   - Adds random parameters (seed, steps, cfg, prompts)
   - Sends workflow to ComfyUI endpoint
   - Polls for completion and displays result

3. **Reproducibility**:
   - All data comes from blockchain
   - Recipe template is immutable
   - Parameters can be customized
   - Complete workflow traceability

## Technical Details

- **Frontend**: Vanilla JavaScript with ethers.js
- **Blockchain**: Base Sepolia testnet
- **Image Generation**: ComfyUI API
- **Wallet**: MetaMask integration
- **Styling**: CSS Grid and Flexbox

## Troubleshooting

- **MetaMask not detected**: Install MetaMask browser extension
- **Network errors**: Check ComfyUI endpoint is accessible
- **Contract errors**: Verify contract addresses are correct
- **Generation fails**: Check ComfyUI server logs

## Development

To modify the frontend:

1. Edit `index.html` for UI changes
2. Edit `app.js` for functionality
3. Test with local web server
4. Deploy to any static hosting service

## Security Notes

- This is a demo frontend for testing
- Never use real private keys in production
- Validate all inputs server-side
- Use HTTPS in production

