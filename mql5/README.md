# TradeMind MQL5 Suite

This folder contains the MetaTrader 5 Expert Advisors and Indicators for TradeMind.

---

## Quick Reference

| File | Type | Purpose |
|------|------|---------|
| **ChartSnapshotEA.mq5** | Expert Advisor | Captures chart screenshots and sends to TradeMind |
| **MarketStructureChannels.mq5** | Indicator | Market structure analysis (HH/HL/LH/LL, BOS, CHoCH) |
| **LiquidityMap.mq5** | Indicator | Liquidity detection (equal highs/lows, sweeps, wick pools) |
| **SmartMoneyContinuation.mq5** | Indicator | Trade signals (3-step continuation model after sweeps) |

---

# ChartSnapshotEA.mq5

Expert Advisor that captures chart screenshots and sends them to TradeMind for AI-powered price action analysis.

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

---

# MarketStructureChannels.mq5

Analyzes market structure by detecting swing points, classifying them, and identifying structure breaks.

## What It Shows

| Label | Meaning |
|-------|---------|
| **HH** | Higher High - bullish structure |
| **HL** | Higher Low - bullish structure |
| **LH** | Lower High - bearish structure |
| **LL** | Lower Low - bearish structure |
| **BOS** | Break of Structure - trend continuation (price broke past previous swing) |
| **CHoCH** | Change of Character - trend reversal (structure broke against trend) |
| **iBOS** | Internal BOS - smaller timeframe structure break |
| **iCHoCH** | Internal CHoCH - smaller timeframe reversal |
| **Range H** | Range High - top of consolidation zone |
| **Range L** | Range Low - bottom of consolidation zone |

## Input Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpSwingStrength` | 5 | Bars each side to confirm a swing point |
| `InpMaxBars` | 500 | Maximum bars to analyze |
| `InpLevelBars` | 20 | Horizontal level line length (bars forward) |
| `InpShowLevels` | true | Show horizontal lines at swing points |
| `InpShowSwingLabels` | true | Show HH/HL/LH/LL labels |
| `InpShowBOS` | true | Show BOS labels |
| `InpShowCHoCH` | true | Show CHoCH labels |
| `InpShowRangeZones` | false | Show accumulation/distribution zones |
| `InpShowInternalBreaks` | false | Show internal (LTF) structure breaks |
| `InpInternalStrength` | 2 | Swing strength for internal structure |

## Colors

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `InpBullLevelColor` | DodgerBlue | Bullish swing levels (HH, HL) |
| `InpBearLevelColor` | Crimson | Bearish swing levels (LH, LL) |
| `InpBOSColor` | DodgerBlue | BOS labels |
| `InpCHoCHColor` | OrangeRed | CHoCH labels |
| `InpHHColor` | Lime | HH labels |
| `InpHLColor` | MediumSeaGreen | HL labels |
| `InpLHColor` | Tomato | LH labels |
| `InpLLColor` | Red | LL labels |
| `InpRangeColor` | Gold | Range zone fill |
| `InpInternalColor` | MediumPurple | Internal break labels |

## How to Use

1. **Trend Identification**: Look for HH + HL = uptrend, LH + LL = downtrend
2. **Continuation**: BOS confirms trend is continuing
3. **Reversal Warning**: CHoCH signals potential trend change
4. **Entry Zones**: Range zones show accumulation/distribution areas

---

# LiquidityMap.mq5

Detects where liquidity pools exist (stop losses clustered) and when they get swept.

## What It Shows

| Label | Meaning |
|-------|---------|
| **EQH x2** | Equal Highs with 2 touches - buy-side liquidity (stop losses above) |
| **EQL x3** | Equal Lows with 3 touches - sell-side liquidity (stop losses below) |
| **(swept)** | Liquidity has been taken - level is no longer active |
| **SWEEP** | Arrow marking where liquidity was grabbed |
| **Wick Pool 4x** | Cluster of 4 rejection wicks at similar price |
| **Range H** | Range high boundary (when ranges enabled) |
| **Range L** | Range low boundary (when ranges enabled) |

## Visual States

| State | Line Style | Color | Meaning |
|-------|------------|-------|---------|
| Untapped | Solid, thick | Orange/Blue | Liquidity still available to be grabbed |
| Swept | Dotted, thin | Gray | Liquidity has been taken |

## Input Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpSwingStrength` | 3 | Bars each side to confirm swing |
| `InpMaxBars` | 500 | Maximum bars to analyze |
| `InpLevelBars` | 30 | Level line length |
| `InpEqualTolerance` | 0.3 | % of ATR for "equal" price matching |
| `InpMinEqualTouches` | 2 | Minimum touches to form equal level |
| `InpATRPeriod` | 14 | ATR period for dynamic tolerance |
| `InpShowEqualHighs` | true | Show equal highs (buy-side liq) |
| `InpShowEqualLows` | true | Show equal lows (sell-side liq) |
| `InpShowSweeps` | true | Show liquidity sweeps |
| `InpShowWickPools` | true | Show wick rejection clusters |
| `InpShowSweepArrows` | true | Show arrows at sweep locations |
| `InpShowRanges` | false | Show consolidation ranges |

## Colors

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `InpEqualHighColor` | OrangeRed | Untapped equal highs |
| `InpEqualLowColor` | DodgerBlue | Untapped equal lows |
| `InpSweptHighColor` | DimGray | Swept highs |
| `InpSweptLowColor` | DimGray | Swept lows |
| `InpSweepArrowColor` | Gold | Sweep arrows |
| `InpWickPoolColor` | MediumPurple | Wick pool zones |
| `InpRangeHighColor` | OrangeRed | Range high lines |
| `InpRangeLowColor` | DodgerBlue | Range low lines |
| `InpRangeFillColor` | Gold | Range zone fill |

## How to Use

1. **Identify Targets**: Untapped EQH/EQL = likely price targets (liquidity grabs)
2. **Wait for Sweep**: When price sweeps a level, look for reversal
3. **Wick Pools**: Clusters of rejections = strong S/R zones
4. **Swept Levels**: Gray dotted lines = liquidity already taken, less relevant

---

# SmartMoneyContinuation.mq5

The main trading signal indicator. Implements a rule-based continuation model after liquidity sweeps.

## The 3-Step Model

After detecting a sweep, checks 3 conditions sequentially:

```
SWEEP DETECTED
     |
     v
[Step 1] Structure Held? (No CHoCH against trend)
     |-- NO --> INVALIDATED
     |-- YES
     v
[Step 2] Displacement Candle? (Body > 70% of range, correct direction)
     |-- NO --> Waiting...
     |-- YES
     v
[Step 3] Pullback Respected OB? (Wick into zone, close outside)
     |-- NO (zone broken) --> INVALIDATED
     |-- YES --> CONTINUATION SIGNAL
```

## What It Shows

| Label | Meaning |
|-------|---------|
| **EQH x2** | Equal Highs with 2 wick touches - buy-side liquidity (stop losses above) |
| **EQL x3** | Equal Lows with 3 wick touches - sell-side liquidity (stop losses below) |
| **(swept)** | Equal level has been taken - shown in gray |
| **SA** | Sweep Arrow - gold arrow at liquidity sweep |
| **RANGE - Fuel** | Sweep within consolidation = fuel for continuation (higher confidence) |
| **HTF EXTREME - Caution** | Sweep at major swing H/L = potential reversal (lower confidence) |
| **DP** | Displacement arrow marker |
| **DISP** | Displacement label - impulsive candle confirmed |
| **Demand OB** | Bullish order block zone (blue rectangle) |
| **Supply OB** | Bearish order block zone (red rectangle) |
| **CONTINUATION** | Final signal - all 3 conditions passed, entry allowed |

## Dashboard (Top-Left)

Shows real-time checklist for each detected sweep:

```
------------------------------------------------------------
 SmartMoneyContinuation v1.0 | EURUSD H1
------------------------------------------------------------
 ATR(14): 0.00142 | Sweeps: 3 | Signals: 1

 #1 BULLISH sweep @ 1.08230 [RANGE SWEEP - Fuel]
    [X] Structure held
    [X] Displacement confirmed
    [X] Pullback respected -> CONTINUATION SIGNAL

 #2 BEARISH sweep @ 1.09150 [HTF EXTREME - Caution]
    [X] Structure held
    [X] Displacement confirmed
    [ ] Waiting for pullback...
------------------------------------------------------------
```

## Sweep Direction Logic

| Sweep Type | What Happened | Expected Move |
|------------|---------------|---------------|
| **BULLISH** | Price swept below equal lows (grabbed sell-side liquidity) | UP |
| **BEARISH** | Price swept above equal highs (grabbed buy-side liquidity) | DOWN |

## Input Parameters

**Detection:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpSwingStrength` | 5 | Bars each side for normal swings |
| `InpHTFSwingStrength` | 10 | Bars each side for HTF extremes |
| `InpMaxBars` | 500 | Maximum bars to analyze |
| `InpLevelBars` | 20 | OB zone forward extension |
| `InpDisplacementRatio` | 0.7 | Min body/range ratio for displacement (70%) |
| `InpATRPeriod` | 14 | ATR period |
| `InpEqualTolerance` | 0.3 | ATR multiplier for equal level tolerance (0.3 = 30% of ATR) |
| `InpMaxBarsAfterSweep` | 20 | Window to find displacement after sweep |
| `InpMaxBarsPullback` | 30 | Window to find pullback after displacement |

**Toggles:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpShowSweepArrows` | true | Show gold sweep arrows |
| `InpShowDisplacement` | true | Show displacement markers |
| `InpShowZones` | true | Show order block rectangles |
| `InpShowSignals` | true | Show CONTINUATION signals |
| `InpShowContextLabels` | true | Show Fuel/Caution labels |
| `InpShowDashboard` | true | Show top-left checklist |
| `InpShowEqualHighs` | true | Show equal highs (buy-side liquidity) |
| `InpShowEqualLows` | true | Show equal lows (sell-side liquidity) |
| `InpMinEqualTouches` | 2 | Minimum touches to form equal level |

**Colors:**

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `InpSweepArrowColor` | Gold | Sweep arrows |
| `InpDisplaceBullColor` | Lime | Bullish displacement |
| `InpDisplaceBearColor` | Red | Bearish displacement |
| `InpDemandZoneColor` | DodgerBlue | Demand OB zones |
| `InpSupplyZoneColor` | Crimson | Supply OB zones |
| `InpSignalBullColor` | Lime | Bullish CONTINUATION |
| `InpSignalBearColor` | Red | Bearish CONTINUATION |
| `InpContextFuelColor` | Gold | "RANGE - Fuel" labels |
| `InpContextCautionColor` | OrangeRed | "HTF EXTREME - Caution" labels |
| `InpEqualHighColor` | OrangeRed | Equal highs color (untapped) |
| `InpEqualLowColor` | DodgerBlue | Equal lows color (untapped) |
| `InpEqualSweptColor` | DimGray | Swept equal level color |
| `InpEqualLineWidth` | 2 | Equal level line width |

## How to Trade

1. **Wait for CONTINUATION signal** - don't enter on sweep alone
2. **Check context**:
   - "RANGE - Fuel" = higher confidence, normal position size
   - "HTF EXTREME - Caution" = lower confidence, reduce size or skip
3. **Entry**: At the signal candle close or on pullback to OB zone
4. **Stop Loss**: Below/above the OB zone (demand low / supply high)
5. **Take Profit**: Next liquidity level or structure point

---

# Recommended Indicator Combinations

## For Learning Structure
Use **MarketStructureChannels** alone to understand:
- How trends form (HH/HL vs LH/LL)
- Where structure breaks occur
- What CHoCH looks like

## For Identifying Targets
Use **LiquidityMap** to see:
- Where stops are clustered (equal highs/lows)
- Which levels have been swept
- Where price might hunt next

## For Trade Signals
Use **SmartMoneyContinuation** which combines:
- Liquidity sweeps (from LiquidityMap logic)
- Structure analysis (from MarketStructureChannels logic)
- Order blocks and displacement
- All wrapped in a 3-step checklist

## Full Stack (Advanced)
Run all three together:
1. **MarketStructureChannels** (lower opacity) for overall structure context
2. **LiquidityMap** for additional liquidity levels not in SMC
3. **SmartMoneyContinuation** for actual trade signals

---

# Indicator Installation

1. Copy `.mq5` files to: `MT5_Directory/MQL5/Indicators/`
2. Restart MetaTrader 5 or refresh Navigator
3. Drag indicator onto chart
4. Adjust input parameters as needed

---

# Glossary

| Term | Definition |
|------|------------|
| **ATR** | Average True Range - measure of volatility |
| **BOS** | Break of Structure - price breaks past a swing point in trend direction |
| **CHoCH** | Change of Character - price breaks structure against the trend |
| **Displacement** | Large-bodied candle showing institutional intent |
| **EQH** | Equal Highs - multiple bar wicks touching similar price |
| **EQL** | Equal Lows - multiple bar wicks touching similar price |
| **HTF** | Higher Time Frame |
| **Liquidity** | Clustered stop losses that institutions target |
| **OB** | Order Block - last consolidation candle before impulse move |
| **SMC** | Smart Money Concepts - trading methodology |
| **Sweep** | Price quickly pierces a level to grab stops, then reverses |
| **Wick Pool** | Cluster of candle wicks showing repeated rejection |

---

# Version History

| File | Version | Notes |
|------|---------|-------|
| ChartSnapshotEA | 1.0 | Chart capture and TradeMind integration |
| MarketStructureChannels | 2.0 | Removed diagonal trendlines, added horizontal levels |
| LiquidityMap | 1.0 | Added range detection toggle |
| SmartMoneyContinuation | 1.0 | Initial release with 3-step model |
