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
          content: `You are a price action analyst doing quick triage on trading charts.
Your job is to quickly assess if a chart shows potential trading setup worth detailed analysis.

Score 0-100 based on:
- Clear market structure (trends, ranges, structure breaks)
- Visible key levels (support/resistance, round numbers)
- Price action signals (wicks, displacement candles)
- Clean price delivery (not choppy/noisy)
- Proximity to key zones where setups form

Respond with JSON only:
{
  "score": <number 0-100>,
  "summary": "<1-2 sentence assessment>",
  "bias": "bullish" | "bearish" | "neutral",
  "has_potential": <boolean - true if score >= 50>
}`
        },
        {
          role: "user",
          content: [
            { type: "text", text: "Analyze this chart for trading potential:" },
            {
              type: "image_url",
              image_url: { url: `data:image/png;base64,${imageBase64}` }
            }
          ]
        }
      ],
      response_format: { type: "json_object" },
      max_tokens: 300
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
    const systemPrompt = `You are an expert price action analyst specializing in institutional order flow concepts.
Analyze charts using these frameworks (score each 0-100):

1. MARKET STRUCTURE (25% weight):
   - HH/HL sequences (uptrend), LH/LL sequences (downtrend)
   - BOS (Break of Structure) - price breaking previous swing point with momentum
   - CHOCH (Change of Character) - first sign of trend reversal
   - Range/consolidation vs trending states, transition zones

2. KEY LEVELS (20% weight):
   - Support and resistance derived from structure
   - S/R flips (resistance becomes support and vice versa)
   - Consolidation highs/lows
   - Previous session highs/lows where visible
   - Round/psychological numbers

3. LIQUIDITY (15% weight):
   - Equal highs/equal lows (liquidity pools)
   - Stops resting above highs and below lows
   - Sweep + reclaim behavior (price takes liquidity then reverses)
   - Failed breakdowns/breakouts

4. IMPULSE & ORIGIN (15% weight):
   - Impulsive vs corrective price legs
   - Origin of strong impulsive moves (order-block-like behavior)
   - Base → expansion patterns
   - Compression → expansion sequences

5. IMBALANCE (15% weight):
   - Price imbalances/inefficiencies (Fair Value Gap-like behavior)
   - Low-overlap displacement candles
   - Rebalancing into inefficient zones

6. CANDLE ACTION (10% weight):
   - Rejection wicks at key levels
   - Strong displacement candles
   - Indecision candles at important zones
   - Acceptance vs rejection (close relative to range)

ENTRY LOGIC REQUIREMENTS:
- Location-based entries (zones, not single ticks)
- With-trend setups prioritized
- Entry only after liquidity interaction
- Clear invalidation level required
- If confluences are insufficient, return valid_setup: false

Respond with JSON matching this exact structure:
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
  "overall_assessment": "2-3 sentence summary",
  "weighted_score": 0-100
}

If no valid setup exists, set entry_logic.valid_setup to false and overall_assessment should state "No valid trade setup identified" with explanation.`;

    // Build user prompt with optional HTF context
    let userPrompt = `Analyze this ${symbol} ${timeframe} chart for trading opportunities using pure price action analysis.

Provide comprehensive analysis of all confluence categories. Calculate weighted_score as:
- Market Structure: 25%
- Key Levels: 20%
- Liquidity: 15%
- Impulse Origin: 15%
- Imbalance: 15%
- Candle Action: 10%

Only identify a valid setup if multiple confluences align. Be conservative - it's better to miss a trade than force a bad one.`;

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
EXISTING ANALYSIS DATA (use this to guide your annotations):
- Trend: ${existingAnalysis.market_structure.trend_state}
- BOS Detected: ${existingAnalysis.market_structure.bos_detected}
- CHOCH Detected: ${existingAnalysis.market_structure.choch_detected}
- Support Levels: ${existingAnalysis.key_levels.support_levels.join(", ") || "none"}
- Resistance Levels: ${existingAnalysis.key_levels.resistance_levels.join(", ") || "none"}
- S/R Flips: ${existingAnalysis.key_levels.sr_flips.join(", ") || "none"}
- Equal Highs: ${existingAnalysis.liquidity.equal_highs.join(", ") || "none"}
- Equal Lows: ${existingAnalysis.liquidity.equal_lows.join(", ") || "none"}
- Sweep Detected: ${existingAnalysis.liquidity.sweep_detected}
- Trade Direction: ${existingAnalysis.entry_logic.trade_direction}
- Entry Zone: ${existingAnalysis.entry_logic.entry_zone}
- Invalidation: ${existingAnalysis.entry_logic.invalidation_level}
- Targets: ${existingAnalysis.entry_logic.targets.join(", ") || "none"}
- Overall: ${existingAnalysis.overall_assessment}
` : "";

    const response = await openai.chat.completions.create({
      model: "gpt-4o",
      messages: [
        {
          role: "system",
          content: `You are a chart annotation specialist. Your job is to identify key price action elements on a trading chart and provide their VISUAL POSITIONS for annotation overlays.

You must analyze the chart image and identify where specific trading concepts appear VISUALLY on the chart. Return positions as percentages (0-100) of the image dimensions:
- x: 0 = left edge, 100 = right edge
- y: 0 = top edge, 100 = bottom edge

For each annotation, provide:
1. A short label (max 25 chars) that will appear on the chart
2. A description explaining what it represents
3. The visual position (x, y) as percentages where the label should appear
4. For horizontal levels, also provide lineY (the y% where the line should be drawn)
5. The price level if identifiable
6. The type and color

ANNOTATION TYPES AND COLORS:
- entry: Green (#22c55e) - Entry zones
- target: Emerald (#10b981) - Take profit targets
- support: Green (#22c55e) - Support levels
- resistance: Red (#ef4444) - Resistance levels
- bos: Blue (#3b82f6) - Break of structure
- choch: Purple (#a855f7) - Change of character
- liquidity: Orange (#f97316) - Liquidity pools (equal highs/lows)
- fvg: Yellow (#eab308) - Fair value gaps / imbalances
- orderblock: Blue (#3b82f6) - Order blocks / origin zones
- sweep: Cyan (#06b6d4) - Liquidity sweeps

IMPORTANT POSITIONING RULES:
1. Place labels NEAR but NOT OVERLAPPING the feature they describe
2. Use the RIGHT side of the chart for most labels (x: 65-95)
3. For horizontal levels, the label should be at the same y-position as the level
4. Avoid clustering - spread annotations vertically
5. Entry zones should be prominently labeled
6. Target levels should be above (for longs) or below (for shorts) entry

Return JSON:
{
  "annotations": [
    {
      "id": "unique-id",
      "label": "Short label",
      "description": "What this represents",
      "type": "entry|target|support|resistance|bos|choch|liquidity|fvg|orderblock|sweep",
      "x": 0-100,
      "y": 0-100,
      "lineY": 0-100 (optional, for horizontal lines),
      "price": number (optional),
      "color": "#hexcolor"
    }
  ],
  "summary": "Brief summary of the chart setup"
}`
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: `Analyze this ${symbol} ${timeframe} chart and provide visual annotations for key price action elements.
${analysisContext}
Identify and annotate:
1. Key support/resistance levels with their prices
2. Entry zone (if valid setup exists)
3. Target levels (TP1, TP2, etc.)
4. Any BOS (break of structure) or CHOCH (change of character)
5. Liquidity pools (equal highs/lows)
6. Order blocks or origin zones
7. FVG/imbalance zones
8. Liquidity sweeps

Place annotations at their VISUAL positions on this specific chart image. Be precise about where elements appear.`
            },
            {
              type: "image_url",
              image_url: { url: `data:image/png;base64,${imageBase64}` }
            }
          ]
        }
      ],
      response_format: { type: "json_object" },
      max_tokens: 2000
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
