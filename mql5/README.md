# TradeMind Chart Snapshot EA

Expert Advisor for MetaTrader 5 that captures chart screenshots and sends them to TradeMind for AI-powered price action analysis.

## Features

- **Automatic Screenshot Capture**: Captures charts at configurable intervals
- **New Bar Trigger**: Optionally capture on new bar formation
- **Multi-Timeframe Support**: Monitor specific timeframes only
- **Secure Communication**: Uses your MT5 account's ingestion key for authentication
- **Base64 Encoding**: Screenshots are encoded and sent as JSON payloads

## Installation

### Step 1: Copy EA File

1. Open MetaTrader 5
2. Go to **File > Open Data Folder**
3. Navigate to `MQL5/Experts/`
4. Copy `ChartSnapshotEA.mq5` to this folder
5. Restart MetaTrader 5 or refresh the Navigator panel

### Step 2: Compile the EA

1. Open **MetaEditor** (press F4 in MT5)
2. In the Navigator, find `ChartSnapshotEA.mq5`
3. Double-click to open it
4. Press **F7** or click **Compile**
5. Ensure there are no errors in the output

### Step 3: Enable WebRequest

**IMPORTANT**: MT5 blocks web requests by default. You must whitelist your server URL.

1. In MetaTrader 5, go to **Tools > Options**
2. Click the **Expert Advisors** tab
3. Check **Allow WebRequest for listed URL**
4. Click **Add** and enter your server URL (e.g., `http://localhost:3000` or your production URL)
5. Click **OK**

### Step 4: Get Your Ingestion Key

1. Open TradeMind in your browser
2. Go to **Settings > MT5 Accounts**
3. Find your account and copy the **Ingestion Key**
4. Keep this key secret - it authenticates your EA

### Step 5: Attach EA to Chart

1. In MT5, open a chart for the symbol you want to monitor
2. In the Navigator panel, find **Expert Advisors > ChartSnapshotEA**
3. Drag and drop it onto your chart
4. Configure the input parameters (see below)
5. Click **OK**

## Input Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Server URL** | `http://localhost:3000` | Your TradeMind server URL |
| **Ingestion Key** | *(empty)* | Your MT5 account's ingestion key from TradeMind settings |
| **Capture Interval (minutes)** | `15` | How often to capture screenshots (0 to disable timer) |
| **Capture On New Bar** | `true` | Also capture when a new bar forms |
| **Image Width** | `1920` | Screenshot width in pixels |
| **Image Height** | `1080` | Screenshot height in pixels |
| **Show Indicators** | `true` | Include indicators in the screenshot |
| **Timeframes** | `M15,H1,H4,D1` | Comma-separated list of timeframes to monitor |

## How It Works

1. **Capture**: The EA captures a PNG screenshot of the chart
2. **Encode**: The image is converted to Base64 format
3. **Send**: A JSON payload is sent to your TradeMind server via HTTP POST
4. **Analysis**: TradeMind's AI analyzes the chart for:
   - Market structure (HH/HL, BOS, CHOCH)
   - Key support/resistance levels
   - Liquidity zones
   - Order blocks and imbalances
   - Entry opportunities with invalidation levels

## Workflow

```
MT5 Chart → Screenshot → Base64 → JSON → TradeMind Server
                                              ↓
                                    Pre-Analysis (GPT-4o-mini)
                                              ↓
                                    Score >= 60? → Full Analysis (GPT-5)
                                              ↓
                                    Review Queue in UI
```

## Troubleshooting

### "WebRequest failed. Error: 4014"
You haven't whitelisted your server URL. See Step 3 above.

### "Invalid ingestion key"
1. Check that you copied the full ingestion key
2. Verify the key hasn't been regenerated in TradeMind
3. Ensure your MT5 account is active in TradeMind

### "Failed to capture screenshot"
1. Make sure the chart is visible and not minimized
2. Check that you have write permissions to the MT5 data folder
3. Reduce image dimensions if running low on memory

### Snapshots Not Appearing in TradeMind
1. Check the Experts tab in MT5 for error messages
2. Verify your server is running and accessible
3. Ensure the timeframe you're on is in the monitored list

## Security Notes

- **Never share your ingestion key** - treat it like a password
- If you suspect your key is compromised, regenerate it in TradeMind Settings
- The EA only sends data TO your server, it doesn't receive trading commands

## Recommended Setup

For optimal analysis, we recommend:

1. **Clean charts**: Use minimal indicators for clearer price action
2. **Multiple timeframes**: Attach the EA to H1 and H4 charts for confluence
3. **Capture interval**: 15-30 minutes is usually sufficient
4. **Review regularly**: Check the Setups page in TradeMind to approve/discard snapshots

## Support

If you encounter issues:
1. Check the Experts and Journal tabs in MT5 for error messages
2. Verify your server is running (`npm run dev`)
3. Test the API endpoint with a tool like Postman
