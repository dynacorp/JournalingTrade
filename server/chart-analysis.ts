import OpenAI from "openai";
import type { ChartSnapshot, FullAnalysisResult } from "@shared/schema";
import { storage } from "./storage";

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

// Pre-analysis threshold for auto-triggering full analysis
const PRE_ANALYSIS_THRESHOLD = 60;

export interface PreAnalysisResult {
  score: number;
  summary: string;
  bias: "bullish" | "bearish" | "neutral";
  has_potential: boolean;
}

export async function runPreAnalysis(imageBase64: string): Promise<PreAnalysisResult> {
  try {
    const response = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: `You are a STRICT price action analyst performing triage on trading charts.
Your job is to quickly assess if a chart warrants detailed analysis. Be CONSERVATIVE - only high-quality charts should pass.

SCORING CRITERIA (be strict):

80-100: EXCELLENT - Clear trend, visible structure breaks, price at key zone, clean delivery
- Must have: Clear BOS or CHOCH visible, price at/near key level, clean candles
- This chart DESERVES full analysis

60-79: GOOD - Decent structure, some key levels visible, reasonable setup potential
- Has structure but may lack one confluence
- Worth analyzing but don't get excited

40-59: MEDIOCRE - Messy structure, choppy price action, no clear setup forming
- Too much noise to trade confidently
- SKIP unless nothing else available

0-39: POOR - No discernible structure, random price action, avoid
- Choppy, no trend, no levels, waste of analysis time
- Do NOT pass to full analysis

BIAS DETERMINATION:
- bullish: Clear uptrend (HH/HL) OR bullish reversal setup (CHOCH up after downtrend)
- bearish: Clear downtrend (LH/LL) OR bearish reversal setup (CHOCH down after uptrend)
- neutral: Ranging, consolidating, or unclear direction

BE HONEST. Most charts are NOT worth analyzing. Score 60+ should be reserved for genuinely promising setups.

Respond with JSON only:
{
  "score": <number 0-100>,
  "summary": "<1-2 sentence HONEST assessment - explain what you see or don't see>",
  "bias": "bullish" | "bearish" | "neutral",
  "has_potential": <boolean - true if score >= 60>
}`
        },
        {
          role: "user",
          content: [
            { type: "text", text: "Triage this chart. Be strict - only pass quality setups to full analysis:" },
            {
              type: "image_url",
              image_url: { url: `data:image/png;base64,${imageBase64}` }
            }
          ]
        }
      ],
      response_format: { type: "json_object" },
      max_tokens: 400
    });

    const result = JSON.parse(response.choices[0].message.content || "{}");

    return {
      score: typeof result.score === "number" ? result.score : 0,
      summary: result.summary || "Unable to analyze chart",
      bias: ["bullish", "bearish", "neutral"].includes(result.bias) ? result.bias : "neutral",
      has_potential: result.has_potential ?? result.score >= 50,
    };
  } catch (error) {
    console.error("Pre-analysis failed:", error);
    return {
      score: 0,
      summary: "Pre-analysis failed - please try again",
      bias: "neutral",
      has_potential: false,
    };
  }
}

export async function runFullAnalysis(
  imageBase64: string,
  symbol: string,
  timeframe: string,
  htfContext?: string
): Promise<FullAnalysisResult> {
  try {
    const systemPrompt = `You are a MASTER institutional price action analyst. Your analysis determines real money decisions - treat this with absolute seriousness. You must be BRUTALLY HONEST. If there is no clear setup, say so. NEVER force or fabricate a trade.

## YOUR MANDATE
- Analyze with the precision of a surgeon and the skepticism of a prosecutor
- Every claim must be backed by visible evidence on the chart
- If you cannot clearly identify something, admit it - do not guess
- A "No Trade" conclusion is often the CORRECT conclusion
- Your job is to protect capital first, find opportunities second

## ANALYSIS FRAMEWORK (Score each 0-100 based on CLARITY and STRENGTH of evidence)

### 1. MARKET STRUCTURE (25% weight)
WHAT TO IDENTIFY:
- Swing highs (HH/LH) and swing lows (HL/LL) - MUST be clearly defined pivots
- BOS (Break of Structure): Price CLOSES beyond previous swing with conviction
- CHOCH (Change of Character): FIRST break against the trend (potential reversal)
- Current state: Trending (clear HH/HL or LH/LL), Ranging (contained highs/lows), Transitioning

SCORING CRITERIA:
- 80-100: Crystal clear structure with recent BOS/CHOCH confirmation
- 60-79: Structure visible but some ambiguity in swing points
- 40-59: Messy/choppy structure, difficult to determine trend
- 0-39: No discernible structure or completely random price action

### 2. KEY LEVELS (20% weight)
WHAT TO IDENTIFY:
- Support: Levels where price BOUNCED UP multiple times with significance
- Resistance: Levels where price REJECTED DOWN multiple times with significance
- S/R Flips: Previous resistance now acting as support (or vice versa) - POWERFUL confluence
- Session levels: Visible daily/weekly highs and lows if discernible

SCORING CRITERIA:
- 80-100: Multiple clean reactions at clearly defined levels
- 60-79: Levels visible with 2+ touches but some ambiguity
- 40-59: Levels are fuzzy, reactions unclear
- 0-39: No meaningful levels visible

### 3. LIQUIDITY (15% weight)
WHAT TO IDENTIFY:
- Equal Highs: 2+ highs at nearly identical price (stop hunt targets above)
- Equal Lows: 2+ lows at nearly identical price (stop hunt targets below)
- Liquidity Sweep: Price pierced beyond equal highs/lows then REVERSED aggressively
- Failed Breakout: Price broke a level but immediately reversed (trap move)

SCORING CRITERIA:
- 80-100: Clear liquidity pools with confirmed sweep and reversal
- 60-79: Liquidity pools visible, sweep in progress or completed
- 40-59: Some equal highs/lows but no clear interaction
- 0-39: No meaningful liquidity patterns visible

### 4. IMPULSE & ORIGIN (15% weight)
WHAT TO IDENTIFY:
- Impulsive moves: Large, directional candles with momentum (displacement)
- Origin zones: The base/consolidation BEFORE an impulsive move (order block concept)
- Compression → Expansion: Tight range followed by explosive move
- Corrective moves: Slow, overlapping candles (pullbacks/retracements)

SCORING CRITERIA:
- 80-100: Clear impulse with identifiable origin zone, price returning to origin
- 60-79: Impulse visible, origin zone somewhat defined
- 40-59: Mixed impulse/corrective action, origin zones unclear
- 0-39: No clear impulse/corrective distinction

### 5. IMBALANCE (15% weight)
WHAT TO IDENTIFY:
- Fair Value Gaps (FVG): Gap between candle 1's high and candle 3's low (bullish) or vice versa
- Displacement candles: Large-bodied candles with minimal wicks (inefficient price delivery)
- Rebalancing: Price returning to fill previously created imbalances

SCORING CRITERIA:
- 80-100: Clear unfilled imbalances with price approaching them
- 60-79: Imbalances visible, partially filled or price may return
- 40-59: Some inefficiencies but already mostly filled
- 0-39: No meaningful imbalances or already completely filled

### 6. CANDLE ACTION (10% weight)
WHAT TO IDENTIFY:
- Rejection wicks: Long wicks showing failed attempts to push price (at key levels = powerful)
- Displacement: Strong bodied candles breaking through levels with authority
- Indecision: Doji/spinning tops at key levels showing equilibrium
- Acceptance vs Rejection: Where did the candle CLOSE relative to key levels?

SCORING CRITERIA:
- 80-100: Clear rejection or acceptance signal at confluence zone
- 60-79: Some candlestick signals but context is mixed
- 40-59: Candles are mixed or inconclusive
- 0-39: No meaningful candle patterns at important levels

## ENTRY LOGIC - THE GATEKEEP

A VALID SETUP REQUIRES **ALL** OF THE FOLLOWING:
1. Clear market structure bias (trend or reversal confirmation)
2. Price at a high-value zone (key level + liquidity + origin/imbalance)
3. Confluence of at least 3 factors pointing to the same direction
4. Defined invalidation level with logical placement (below/above structure)
5. Risk-reward of at least 1:2 to first target

IF ANY OF THESE ARE MISSING → valid_setup: false

CONFIDENCE SCORING FOR ENTRIES:
- 85-100: "A+ Setup" - 4+ confluences, pristine structure, clear invalidation
- 70-84: "B Setup" - 3 confluences, good structure, acceptable invalidation
- 50-69: "C Setup" - 2-3 weak confluences, questionable - AVOID
- 0-49: NO VALID SETUP - Do not trade

## RESPONSE FORMAT (JSON)
{
  "market_structure": {
    "trend_state": "uptrend" | "downtrend" | "range" | "transitioning",
    "structure_points": ["HH at X", "HL at Y", etc.],
    "bos_detected": boolean,
    "choch_detected": boolean,
    "score": 0-100
  },
  "key_levels": {
    "support_levels": [price1, price2],
    "resistance_levels": [price1, price2],
    "sr_flips": [price1],
    "session_levels": { "high": number | null, "low": number | null },
    "score": 0-100
  },
  "liquidity": {
    "equal_highs": [price1],
    "equal_lows": [price1],
    "sweep_detected": boolean,
    "failed_breakout": boolean,
    "score": 0-100
  },
  "impulse_origin": {
    "origin_zones": [{ "start": price, "end": price }],
    "compression_detected": boolean,
    "expansion_detected": boolean,
    "score": 0-100
  },
  "imbalance": {
    "fvg_zones": [{ "start": price, "end": price, "filled": boolean }],
    "rebalancing_in_progress": boolean,
    "score": 0-100
  },
  "candle_action": {
    "rejection_wicks": ["description at level"],
    "displacement_detected": boolean,
    "acceptance_rejection": "acceptance" | "rejection" | "neutral",
    "score": 0-100
  },
  "entry_logic": {
    "valid_setup": boolean,
    "entry_zone": "price range or description",
    "invalidation_level": number,
    "invalidation_reason": "reason",
    "trade_direction": "long" | "short" | "none",
    "targets": [price1, price2],
    "confluence_list": ["confluence1", "confluence2"],
    "confidence": 0-100
  },
  "overall_assessment": "2-3 sentence HONEST summary - if no setup, explain why clearly",
  "weighted_score": 0-100
}

REMEMBER: "No valid setup" is a VALID and often CORRECT conclusion. Your job is TRUTH, not to find trades where none exist.`;

    // Build user prompt with optional HTF context
    let userPrompt = `Analyze this ${symbol} ${timeframe} chart with EXTREME scrutiny.

Your analysis will determine real trading decisions. Be RUTHLESSLY HONEST.

Calculate weighted_score as:
- Market Structure: 25%
- Key Levels: 20%
- Liquidity: 15%
- Impulse Origin: 15%
- Imbalance: 15%
- Candle Action: 10%

CRITICAL RULES:
1. Only identify a valid setup if you would stake YOUR OWN MONEY on it
2. Require minimum 3 strong confluences for any entry
3. If the chart is messy, choppy, or unclear - say "No Setup"
4. Never force a trade just because you were asked to analyze
5. Read the price axis carefully to provide accurate price levels`;

    // Add HTF context for LTF entry analysis
    if (htfContext) {
      userPrompt += `

IMPORTANT - Higher Timeframe Context (use this to confirm bias and direction):
${htfContext}

This is a LOWER TIMEFRAME (${timeframe}) chart for ENTRY timing. Your entry MUST align with the HTF bias above.
- If HTF is bullish, only look for LONG entries
- If HTF is bearish, only look for SHORT entries
- Identify precise entry zones near HTF key levels
- Entry invalidation should be below/above the origin of the LTF move`
    }

    const response = await openai.chat.completions.create({
      model: "gpt-5",
      messages: [
        { role: "system", content: systemPrompt },
        {
          role: "user",
          content: [
            { type: "text", text: userPrompt },
            {
              type: "image_url",
              image_url: { url: `data:image/png;base64,${imageBase64}` }
            }
          ]
        }
      ],
      response_format: { type: "json_object" },
      max_tokens: 3000
    });

    const result = JSON.parse(response.choices[0].message.content || "{}");

    // Ensure all required fields exist with defaults
    return {
      market_structure: {
        trend_state: result.market_structure?.trend_state || "range",
        structure_points: result.market_structure?.structure_points || [],
        bos_detected: result.market_structure?.bos_detected ?? false,
        choch_detected: result.market_structure?.choch_detected ?? false,
        score: result.market_structure?.score ?? 0,
      },
      key_levels: {
        support_levels: result.key_levels?.support_levels || [],
        resistance_levels: result.key_levels?.resistance_levels || [],
        sr_flips: result.key_levels?.sr_flips || [],
        session_levels: result.key_levels?.session_levels || { high: null, low: null },
        score: result.key_levels?.score ?? 0,
      },
      liquidity: {
        equal_highs: result.liquidity?.equal_highs || [],
        equal_lows: result.liquidity?.equal_lows || [],
        sweep_detected: result.liquidity?.sweep_detected ?? false,
        failed_breakout: result.liquidity?.failed_breakout ?? false,
        score: result.liquidity?.score ?? 0,
      },
      impulse_origin: {
        origin_zones: result.impulse_origin?.origin_zones || [],
        compression_detected: result.impulse_origin?.compression_detected ?? false,
        expansion_detected: result.impulse_origin?.expansion_detected ?? false,
        score: result.impulse_origin?.score ?? 0,
      },
      imbalance: {
        fvg_zones: result.imbalance?.fvg_zones || [],
        rebalancing_in_progress: result.imbalance?.rebalancing_in_progress ?? false,
        score: result.imbalance?.score ?? 0,
      },
      candle_action: {
        rejection_wicks: result.candle_action?.rejection_wicks || [],
        displacement_detected: result.candle_action?.displacement_detected ?? false,
        acceptance_rejection: result.candle_action?.acceptance_rejection || "neutral",
        score: result.candle_action?.score ?? 0,
      },
      entry_logic: {
        valid_setup: result.entry_logic?.valid_setup ?? false,
        entry_zone: result.entry_logic?.entry_zone || "",
        invalidation_level: result.entry_logic?.invalidation_level ?? 0,
        invalidation_reason: result.entry_logic?.invalidation_reason || "",
        trade_direction: result.entry_logic?.trade_direction || "none",
        targets: result.entry_logic?.targets || [],
        confluence_list: result.entry_logic?.confluence_list || [],
        confidence: result.entry_logic?.confidence ?? 0,
      },
      overall_assessment: result.overall_assessment || "Analysis completed",
      weighted_score: result.weighted_score ?? 0,
    };
  } catch (error) {
    console.error("Full analysis failed:", error);
    throw new Error("Full analysis failed - please try again");
  }
}

export async function processSnapshot(snapshotId: number): Promise<ChartSnapshot | null> {
  const snapshot = await storage.getChartSnapshot(snapshotId);
  if (!snapshot) return null;

  // Run pre-analysis
  const preResult = await runPreAnalysis(snapshot.image_data);

  await storage.updateChartSnapshot(snapshotId, {
    pre_analysis_score: preResult.score,
    pre_analysis_summary: preResult.summary,
    pre_analysis_bias: preResult.bias,
    pre_analysis_at: new Date(),
    status: "pre_analyzed",
  });

  // Auto-gate: if score exceeds threshold, run full analysis
  if (preResult.score >= PRE_ANALYSIS_THRESHOLD) {
    await storage.updateChartSnapshot(snapshotId, { status: "approved" });
    return await runAndSaveFullAnalysis(snapshotId);
  } else {
    await storage.updateChartSnapshot(snapshotId, { status: "queued_for_review" });
    return (await storage.getChartSnapshot(snapshotId)) ?? null;
  }
}

// Chart annotation interface for visual breakdown
export interface ChartAnnotation {
  id: string;
  label: string;
  description: string;
  type: "entry" | "target" | "support" | "resistance" | "bos" | "choch" | "liquidity" | "fvg" | "orderblock" | "sweep";
  // Position as percentage of image (0-100)
  x: number;
  y: number;
  // Optional: for horizontal lines
  lineY?: number;
  // Optional: price level
  price?: number;
  color: string;
}

export interface ChartAnnotationResult {
  annotations: ChartAnnotation[];
  summary: string;
}

export async function generateChartAnnotations(
  imageBase64: string,
  symbol: string,
  timeframe: string,
  existingAnalysis?: FullAnalysisResult
): Promise<ChartAnnotationResult> {
  try {
    const analysisContext = existingAnalysis ? `
═══════════════════════════════════════════════════════════════
EXISTING ANALYSIS DATA - USE THIS TO GUIDE YOUR ANNOTATIONS
═══════════════════════════════════════════════════════════════
MARKET STRUCTURE:
• Trend State: ${existingAnalysis.market_structure.trend_state}
• Structure Points: ${existingAnalysis.market_structure.structure_points?.join(", ") || "none identified"}
• BOS Confirmed: ${existingAnalysis.market_structure.bos_detected ? "YES ✓" : "NO"}
• CHOCH Confirmed: ${existingAnalysis.market_structure.choch_detected ? "YES ✓" : "NO"}
• Structure Score: ${existingAnalysis.market_structure.score}/100

KEY LEVELS:
• Support: ${existingAnalysis.key_levels.support_levels.join(", ") || "none"}
• Resistance: ${existingAnalysis.key_levels.resistance_levels.join(", ") || "none"}
• S/R Flips: ${existingAnalysis.key_levels.sr_flips.join(", ") || "none"}
• Levels Score: ${existingAnalysis.key_levels.score}/100

LIQUIDITY:
• Equal Highs: ${existingAnalysis.liquidity.equal_highs.join(", ") || "none"}
• Equal Lows: ${existingAnalysis.liquidity.equal_lows.join(", ") || "none"}
• Sweep Detected: ${existingAnalysis.liquidity.sweep_detected ? "YES ✓" : "NO"}
• Failed Breakout: ${existingAnalysis.liquidity.failed_breakout ? "YES ✓" : "NO"}
• Liquidity Score: ${existingAnalysis.liquidity.score}/100

ORDER FLOW:
• Origin Zones: ${existingAnalysis.impulse_origin.origin_zones?.map(z => `${z.start}-${z.end}`).join(", ") || "none"}
• Compression: ${existingAnalysis.impulse_origin.compression_detected ? "YES ✓" : "NO"}
• Expansion: ${existingAnalysis.impulse_origin.expansion_detected ? "YES ✓" : "NO"}

IMBALANCES:
• FVG Zones: ${existingAnalysis.imbalance.fvg_zones?.map(z => `${z.start}-${z.end} (${z.filled ? "filled" : "unfilled"})`).join(", ") || "none"}
• Rebalancing: ${existingAnalysis.imbalance.rebalancing_in_progress ? "IN PROGRESS" : "NO"}

ENTRY LOGIC:
• Valid Setup: ${existingAnalysis.entry_logic.valid_setup ? "YES ✓" : "NO - DO NOT ANNOTATE ENTRY"}
• Direction: ${existingAnalysis.entry_logic.trade_direction}
• Entry Zone: ${existingAnalysis.entry_logic.entry_zone || "none"}
• Invalidation: ${existingAnalysis.entry_logic.invalidation_level || "none"}
• Targets: ${existingAnalysis.entry_logic.targets.join(", ") || "none"}
• Confluences: ${existingAnalysis.entry_logic.confluence_list?.join(", ") || "none"}
• Confidence: ${existingAnalysis.entry_logic.confidence}/100

ASSESSMENT: ${existingAnalysis.overall_assessment}
WEIGHTED SCORE: ${existingAnalysis.weighted_score}/100
═══════════════════════════════════════════════════════════════
` : "";

    const systemPrompt = `You are a MASTER-LEVEL institutional chart annotator. Your annotations will be overlaid on trading charts for professional traders making real money decisions.

═══════════════════════════════════════════════════════════════
YOUR SACRED DUTY
═══════════════════════════════════════════════════════════════
1. PRECISION IS EVERYTHING - Every annotation must be pixel-accurate
2. ONLY ANNOTATE WHAT YOU CAN CLEARLY SEE - Never guess or fabricate
3. READ THE PRICE AXIS CAREFULLY - Get exact price levels from the right side
4. IF NO SETUP EXISTS, ANNOTATE ONLY STRUCTURE - Do not invent entries
5. QUALITY OVER QUANTITY - 5 precise annotations beat 15 sloppy ones

═══════════════════════════════════════════════════════════════
COORDINATE SYSTEM
═══════════════════════════════════════════════════════════════
Return positions as percentages (0-100) of the image:
• x: 0 = left edge, 100 = right edge
• y: 0 = TOP of image (HIGHEST prices), 100 = BOTTOM (LOWEST prices)

CRITICAL: On a price chart, LOWER y-values = HIGHER prices!
If a resistance level is at the top third of the chart, y ≈ 25-35
If a support level is at the bottom third, y ≈ 65-75

═══════════════════════════════════════════════════════════════
WHAT TO ANNOTATE (IN ORDER OF IMPORTANCE)
═══════════════════════════════════════════════════════════════

1. MARKET STRUCTURE (ALWAYS ANNOTATE)
   • BOS (Break of Structure): Where price CLOSES beyond a swing high/low
     - Label: "BOS ↑" or "BOS ↓" with the price
     - Must show clear break with body close, not just wick
   • CHOCH (Change of Character): FIRST break against the trend
     - Label: "CHOCH" - this signals potential reversal
   • Swing Points: Label significant HH, HL, LH, LL with prices

2. KEY LEVELS (ALWAYS ANNOTATE)
   • Resistance: Levels where price rejected DOWN multiple times
     - Label: "Resistance [PRICE]" - use RED (#ef4444)
     - lineY REQUIRED for horizontal line
   • Support: Levels where price bounced UP multiple times
     - Label: "Support [PRICE]" - use GREEN (#22c55e)
     - lineY REQUIRED for horizontal line
   • S/R Flip: Previous resistance now support (or vice versa)
     - Label: "S/R Flip [PRICE]" - POWERFUL confluence

3. LIQUIDITY ZONES
   • Equal Highs: 2+ highs at same price (stops above)
     - Label: "EQH [PRICE]" with triangles pointing up
     - Use ORANGE (#f97316)
   • Equal Lows: 2+ lows at same price (stops below)
     - Label: "EQL [PRICE]" with triangles pointing down
   • Liquidity Sweep: Price pierced EQH/EQL then reversed
     - Label: "Sweep ✓" - CYAN (#06b6d4)

4. ORDER BLOCKS (Origin Zones)
   • The consolidation BEFORE an impulsive move
   • Label: "OB [PRICE RANGE]" - BLUE (#3b82f6)
   • Only annotate if clearly visible candle base before displacement

5. IMBALANCES (FVG - Fair Value Gaps)
   • Gap between candle 1 high and candle 3 low (bullish FVG)
   • Gap between candle 1 low and candle 3 high (bearish FVG)
   • Label: "FVG [PRICE RANGE]" - YELLOW (#eab308)
   • Indicate if filled or unfilled

6. ENTRY/TARGET (ONLY IF VALID SETUP EXISTS)
   ⚠️ CRITICAL: If existing analysis shows valid_setup: false, DO NOT annotate entry!
   • Entry Zone: Where price should enter
     - Label: "ENTRY [PRICE]" - GREEN (#22c55e)
   • Invalidation: Where the trade idea is wrong
     - Label: "INVALID [PRICE]" - RED dashed line
   • Targets: TP1, TP2, etc.
     - Label: "TP1 [PRICE]", "TP2 [PRICE]" - EMERALD (#10b981)

═══════════════════════════════════════════════════════════════
ANNOTATION POSITIONING RULES
═══════════════════════════════════════════════════════════════

1. HORIZONTAL LEVELS: Always provide lineY for S/R, EQH/EQL, entry, targets
   - The label y and lineY should match for the line to go through it
   - Place label text at x: 75-95 (right side of chart)

2. POINT ANNOTATIONS (BOS, CHOCH, sweeps):
   - Place at the actual candle where it occurred
   - x: position along timeline where event happened
   - y: at the price level of the event

3. ZONE ANNOTATIONS (Order blocks, FVG):
   - x: right side (75-90) for visibility
   - y: center of the zone

4. AVOID OVERLAPPING:
   - Space annotations at least 5% apart vertically
   - Use connector lines if label must be offset from actual position

5. LABEL FORMATTING:
   - Include price in label when possible
   - Max 25 characters per label
   - Be concise but clear

═══════════════════════════════════════════════════════════════
ANNOTATION TYPES AND COLORS (STRICT)
═══════════════════════════════════════════════════════════════
• entry: #22c55e (Green) - Entry zones
• target: #10b981 (Emerald) - Take profit levels
• support: #22c55e (Green) - Support levels
• resistance: #ef4444 (Red) - Resistance levels
• bos: #3b82f6 (Blue) - Break of structure
• choch: #a855f7 (Purple) - Change of character
• liquidity: #f97316 (Orange) - Equal highs/lows
• fvg: #eab308 (Yellow) - Fair value gaps
• orderblock: #3b82f6 (Blue) - Order blocks
• sweep: #06b6d4 (Cyan) - Liquidity sweeps

═══════════════════════════════════════════════════════════════
RESPONSE FORMAT (JSON)
═══════════════════════════════════════════════════════════════
{
  "annotations": [
    {
      "id": "unique-id-string",
      "label": "Short label (max 25 chars)",
      "description": "Detailed explanation of what this represents",
      "type": "entry|target|support|resistance|bos|choch|liquidity|fvg|orderblock|sweep",
      "x": 0-100 (percentage from left),
      "y": 0-100 (percentage from top - REMEMBER: lower y = higher price),
      "lineY": 0-100 (REQUIRED for horizontal levels),
      "price": exact_price_from_chart,
      "color": "#hexcolor"
    }
  ],
  "summary": "Professional 2-3 sentence assessment of what the chart shows and its quality as a setup"
}

═══════════════════════════════════════════════════════════════
CRITICAL REMINDERS
═══════════════════════════════════════════════════════════════
• READ THE PRICE AXIS on the right side of the chart for exact levels
• Double-check y-coordinates: HIGH prices = LOW y-values
• If you can't clearly see something, DON'T annotate it
• No valid setup? Annotate structure only, explain why in summary
• Your annotations must be ACTIONABLE for a professional trader`;

    const response = await openai.chat.completions.create({
      model: "gpt-4o",
      messages: [
        {
          role: "system",
          content: systemPrompt
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: `ANALYZE THIS ${symbol} ${timeframe} CHART WITH SURGICAL PRECISION.

Your annotations will be displayed directly on this chart for trading decisions.

${analysisContext}

INSTRUCTIONS:
1. First, carefully READ THE PRICE AXIS on the right side to understand price levels
2. Identify ALL visible market structure (BOS, CHOCH, swing points)
3. Mark ALL clear support and resistance levels with exact prices
4. Identify any liquidity pools (equal highs/lows) and note if swept
5. Mark any visible order blocks (consolidation before impulse moves)
6. Mark any unfilled fair value gaps
7. ONLY if a valid setup exists, mark entry, invalidation, and targets

CRITICAL QUALITY CHECKS BEFORE RESPONDING:
□ Did I read the price axis correctly?
□ Are my y-coordinates correct? (lower y = higher price)
□ Do I have lineY for all horizontal levels?
□ Are prices accurate to what's visible on chart?
□ If no valid setup, did I avoid annotating entry/targets?

Provide PROFESSIONAL-GRADE annotations. This is life or death for capital.`
            },
            {
              type: "image_url",
              image_url: {
                url: `data:image/png;base64,${imageBase64}`,
                detail: "high"  // Request high detail for better price reading
              }
            }
          ]
        }
      ],
      response_format: { type: "json_object" },
      max_tokens: 3000  // Increased for more detailed annotations
    });

    const result = JSON.parse(response.choices[0].message.content || "{}");

    return {
      annotations: (result.annotations || []).map((a: ChartAnnotation, i: number) => ({
        id: a.id || `annotation-${i}`,
        label: a.label || "",
        description: a.description || "",
        type: a.type || "support",
        x: Math.max(0, Math.min(100, a.x || 50)),
        y: Math.max(0, Math.min(100, a.y || 50)),
        lineY: a.lineY !== undefined ? Math.max(0, Math.min(100, a.lineY)) : undefined,
        price: a.price,
        color: a.color || "#ffffff",
      })),
      summary: result.summary || "Chart analysis complete",
    };
  } catch (error) {
    console.error("Chart annotation generation failed:", error);
    return {
      annotations: [],
      summary: "Failed to generate annotations",
    };
  }
}

export async function runAndSaveFullAnalysis(snapshotId: number): Promise<ChartSnapshot | null> {
  const snapshot = await storage.getChartSnapshot(snapshotId);
  if (!snapshot) return null;

  try {
    // Check if this is part of a group
    let htfContext: string | undefined;
    if (snapshot.group_id && snapshot.tf_type === "ltf") {
      // Get HTF snapshots from the same group for context
      const groupSnapshots = await storage.getChartSnapshotsByGroupId(snapshot.group_id);
      const htfSnapshots = groupSnapshots.filter(s => s.tf_type === "htf" && s.full_analysis);

      if (htfSnapshots.length > 0) {
        // Build context from HTF analysis
        htfContext = htfSnapshots.map(htf => {
          const analysis = JSON.parse(htf.full_analysis || "{}");
          return `${htf.timeframe} Bias: ${analysis.market_structure?.trend_state || "unknown"}, ` +
                 `Structure: ${analysis.market_structure?.structure_points?.join(", ") || "N/A"}, ` +
                 `Key Levels: S${analysis.key_levels?.support_levels?.join(",") || "N/A"} / R${analysis.key_levels?.resistance_levels?.join(",") || "N/A"}`;
        }).join("\n");
      }
    }

    const fullResult = await runFullAnalysis(
      snapshot.image_data,
      snapshot.symbol,
      snapshot.timeframe,
      htfContext
    );

    const isValidSetup = fullResult.entry_logic.valid_setup;
    const newStatus = isValidSetup ? "analyzed" : "no_setup";

    await storage.updateChartSnapshot(snapshotId, {
      full_analysis: JSON.stringify(fullResult),
      full_analysis_at: new Date(),
      status: newStatus,
      confluence_score: fullResult.weighted_score,
      market_structure_score: fullResult.market_structure.score,
      key_levels_score: fullResult.key_levels.score,
      liquidity_score: fullResult.liquidity.score,
      impulse_origin_score: fullResult.impulse_origin.score,
      imbalance_score: fullResult.imbalance.score,
      candle_action_score: fullResult.candle_action.score,
      trade_direction: fullResult.entry_logic.trade_direction,
      entry_zone: fullResult.entry_logic.entry_zone,
      invalidation_level: fullResult.entry_logic.invalidation_level,
      invalidation_reason: fullResult.entry_logic.invalidation_reason,
      is_journal_candidate: isValidSetup && fullResult.weighted_score >= 70,
    });

    // Try to auto-match with executed trades
    if (isValidSetup) {
      await storage.autoMatchSnapshotToTrade(snapshotId);
    }

    return (await storage.getChartSnapshot(snapshotId)) ?? null;
  } catch (error) {
    console.error("Failed to run full analysis:", error);
    return snapshot;
  }
}
