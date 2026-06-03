//+------------------------------------------------------------------+
//| PAM/ScoringEngine.mqh  —  Educational scoring + narrative       |
//|                                                                  |
//| Produces a composite "structural quality score" (0–100) that    |
//| reflects HOW READABLE the current market is for a skilled       |
//| trader — NOT a prediction of future direction.                  |
//|                                                                  |
//| Also generates a mode-sensitive educational narrative.          |
//+------------------------------------------------------------------+
#ifndef PAM_SCORING_MQH
#define PAM_SCORING_MQH
#include "Context.mqh"

// Forward declaration — defined in PremDiscEngine.mqh which is included after this header
double PremDiscEngine_StructureBonus(const SPAMContext &ctx);

//+------------------------------------------------------------------+
// Internal: clamp helper
//+------------------------------------------------------------------+
double ScoreClamp(double v) { return MathMax(0, MathMin(100, v)); }

//+------------------------------------------------------------------+
// ScoringEngine_Compute
//   Weighs all engine outputs to produce ctx.score.
//   Weights:  structure 30% | liquidity 25% | momentum 20%
//             imbalance 15% | conviction 10%
//+------------------------------------------------------------------+
void ScoringEngine_Compute(SPAMContext &ctx, double curPrice)
{
   // ─── Structure (0–100) ───────────────────────────────────────
   double ss = 0;
   if(ctx.trend == TREND_BULLISH || ctx.trend == TREND_BEARISH) ss += 30;
   if(ctx.trend == TREND_RANGING)                               ss += 10;
   if(ctx.hasBullBOS || ctx.hasBearBOS)                         ss += 20;
   if(ctx.hasBullCHoCH || ctx.hasBearCHoCH)                     ss += 15;
   if(ctx.hasBullMSS   || ctx.hasBearMSS)                       ss += 20;
   if(ctx.htfTrend != TREND_UNDEFINED && ctx.htfTrend == ctx.trend) ss += 15;
   ss += PremDiscEngine_StructureBonus(ctx);
   ctx.score.structure = ScoreClamp(ss);

   // ─── Liquidity (0–100) ───────────────────────────────────────
   double ls = 0;
   if(ctx.nLiq > 0)                             ls += 20;
   if(ctx.nLiq >= 3)                            ls += 10;
   if(ctx.liqSweptBull || ctx.liqSweptBear)     ls += 50;
   int bsl = 0, ssl_cnt = 0;
   for(int i = 0; i < ctx.nLiq; i++)
   {
      if(!ctx.liq[i].swept)
      {
         if(ctx.liq[i].type == LIQ_BUY_SIDE) bsl++;
         else                                  ssl_cnt++;
      }
   }
   if(bsl > 0 && ssl_cnt > 0) ls += 20;
   ctx.score.liquidity = ScoreClamp(ls);

   // ─── Momentum (0–100) ────────────────────────────────────────
   double ms = 0;
   if(ctx.dispBullRecent  || ctx.dispBearRecent)      ms += 50;
   if(ctx.exhaustBullRecent || ctx.exhaustBearRecent)  ms -= 20;
   if(ctx.phase == PHASE_EXPANSION)   ms += 40;
   if(ctx.phase == PHASE_CORRECTIVE)  ms += 20;
   if(ctx.phase == PHASE_COMPRESSION) ms += 10;
   ctx.score.momentum = ScoreClamp(ms);

   // ─── Imbalance (0–100) ───────────────────────────────────────
   double im = 0;
   if(ctx.hasBullFVG || ctx.hasBearFVG)         im += 40;
   if(ctx.hasBullOB  || ctx.hasBearOB)           im += 40;
   if(ctx.hasBullBreaker || ctx.hasBearBreaker)  im += 20;
   ctx.score.imbalance = ScoreClamp(im);

   // ─── Conviction (0–100) ──────────────────────────────────────
   double cv = 0;
   if(ctx.nCandles > 0)
   {
      SCandle c0 = ctx.candles[0];
      cv = c0.bodyRatio * 60.0 + c0.rangeVsAtr * 20.0;
      if(c0.type == CANDLE_DISPLACEMENT_BULL || c0.type == CANDLE_DISPLACEMENT_BEAR)
         cv = 90;
      if(c0.type == CANDLE_INDECISION)  cv = 15;
      if(c0.type == CANDLE_COMPRESSION) cv = 10;
   }
   ctx.score.conviction = ScoreClamp(cv);

   // ─── Composite (weighted) ────────────────────────────────────
   ctx.score.total = ScoreClamp(ctx.score.structure  * 0.30 +
                                ctx.score.liquidity  * 0.25 +
                                ctx.score.momentum   * 0.20 +
                                ctx.score.imbalance  * 0.15 +
                                ctx.score.conviction * 0.10);
}

//+------------------------------------------------------------------+
// Helper: trend word
//+------------------------------------------------------------------+
string TrendWord(ETrend t, bool caps = false)
{
   string w;
   switch(t)
   {
      case TREND_BULLISH:   w = "bullish";   break;
      case TREND_BEARISH:   w = "bearish";   break;
      case TREND_RANGING:   w = "ranging";   break;
      default:              w = "undefined"; break;
   }
   if(caps) { StringToUpper(w); }
   return w;
}

string PhaseWord(EPhase p)
{
   switch(p)
   {
      case PHASE_ACCUMULATION:  return "Accumulation";
      case PHASE_MANIPULATION:  return "Manipulation";
      case PHASE_EXPANSION:     return "Expansion";
      case PHASE_DISTRIBUTION:  return "Distribution";
      case PHASE_COMPRESSION:   return "Compression";
      case PHASE_CORRECTIVE:    return "Corrective";
      case PHASE_TRENDING:      return "Trending";
      default:                  return "Undefined";
   }
}

//+------------------------------------------------------------------+
// ScoringEngine_BuildNarrative
//   Assembles 3–5 educational sentences tailored to EMode.
//   Written from first principles of institutional market reading.
//+------------------------------------------------------------------+
void ScoringEngine_BuildNarrative(SPAMContext &ctx, double curPrice)
{
   string lines[];
   ArrayResize(lines, 0);

   // ─── Line 1: Structure ────────────────────────────────────────
   string structLine = "";
   if(ctx.trend == TREND_BULLISH)
   {
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            structLine = "Uptrend: price is making higher highs and higher lows. "
                         "Buyers are currently in control.";
            break;
         case MODE_ADVANCED:
            structLine = "Bullish market structure intact (HH/HL sequence). "
                         "Look for HL formations to offer continuation entries.";
            break;
         case MODE_INSTITUTIONAL:
            structLine = "Institutional buy-side pressure sustaining HH/HL structure. "
                         "Smart money accumulating on each HL — trail stops below confirmed lows.";
            break;
      }
   }
   else if(ctx.trend == TREND_BEARISH)
   {
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            structLine = "Downtrend: price is making lower highs and lower lows. "
                         "Sellers are in control.";
            break;
         case MODE_ADVANCED:
            structLine = "Bearish market structure intact (LH/LL sequence). "
                         "Look for LH rallies to offer continuation entries.";
            break;
         case MODE_INSTITUTIONAL:
            structLine = "Institutional sell-side flow maintaining LH/LL structure. "
                         "Distribution occurring on each LH — look for OB reaction before next leg.";
            break;
      }
   }
   else if(ctx.trend == TREND_RANGING)
   {
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            structLine = "No clear trend — price is moving sideways. "
                         "Avoid trading against both extremes until a breakout occurs.";
            break;
         case MODE_ADVANCED:
            structLine = "Ranging conditions: no sustained HH/HL or LH/LL sequence. "
                         "Watch for liquidity sweeps at range extremes before choosing direction.";
            break;
         case MODE_INSTITUTIONAL:
            structLine = "Market in equilibrium — institutions potentially building a position. "
                         "Range extremes contain stop clusters; expect engineered moves before breakout.";
            break;
      }
   }
   else
   {
      structLine = "Market structure not yet defined — wait for a confirmed swing sequence.";
   }

   int n = ArraySize(lines);
   ArrayResize(lines, n + 1);
   lines[n] = structLine;

   // ─── Line 2: CHoCH / BOS / MSS ───────────────────────────────
   if(ctx.hasBullMSS || ctx.hasBearMSS)
   {
      string mssLine = "";
      bool isBull = ctx.hasBullMSS;
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            mssLine = isBull
               ? "A strong bullish candle just broke the downtrend — this may be a reversal."
               : "A strong bearish candle just broke the uptrend — this may be a reversal.";
            break;
         case MODE_ADVANCED:
            mssLine = isBull
               ? "Market Structure Shift (MSS) bullish — momentum displacement broke bearish structure."
               : "Market Structure Shift (MSS) bearish — momentum displacement broke bullish structure.";
            break;
         case MODE_INSTITUTIONAL:
            mssLine = isBull
               ? "MSS bullish: institutional displacement absorbed sell-side liquidity and broke structure. "
                 "Potential redistribution of positions. Look for first OB on pullback."
               : "MSS bearish: institutional displacement absorbed buy-side liquidity and broke structure. "
                 "Smart money potentially reallocating short. Watch for bearish OB retest.";
            break;
      }
      n = ArraySize(lines); ArrayResize(lines, n + 1); lines[n] = mssLine;
   }
   else if(ctx.hasBullCHoCH || ctx.hasBearCHoCH)
   {
      bool isBull = ctx.hasBullCHoCH;
      string chochLine = "";
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            chochLine = isBull
               ? "Warning: price broke above a key high — the downtrend may be ending."
               : "Warning: price broke below a key low — the uptrend may be ending.";
            break;
         case MODE_ADVANCED:
            chochLine = isBull
               ? "CHoCH bullish detected: trend reversal signal. Confirmation needed."
               : "CHoCH bearish detected: trend reversal signal. Confirmation needed.";
            break;
         case MODE_INSTITUTIONAL:
            chochLine = isBull
               ? "CHoCH bullish: possible institutional position flip. Wait for OB mitigation "
                 "or FVG fill on first pullback to confirm new directional bias."
               : "CHoCH bearish: possible institutional position flip. Validate with OB "
                 "and sell-side liquidity sweep before committing to new direction.";
            break;
      }
      n = ArraySize(lines); ArrayResize(lines, n + 1); lines[n] = chochLine;
   }

   // ─── Line 3: Liquidity ────────────────────────────────────────
   string liqLine = "";
   if(ctx.liqSweptBull)
   {
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            liqLine = "Price recently dipped below key lows, triggering stop losses. "
                      "This often precedes a bullish move.";
            break;
         case MODE_ADVANCED:
            liqLine = "Sell-side liquidity swept. Stop-hunt complete. Potential bullish continuation.";
            break;
         case MODE_INSTITUTIONAL:
            liqLine = "Sell-side liquidity pool consumed. Market makers have offloaded short positions "
                      "and may now drive price higher. Watch for bullish displacement after sweep.";
            break;
      }
   }
   else if(ctx.liqSweptBear)
   {
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            liqLine = "Price recently spiked above key highs, triggering stop losses. "
                      "This often precedes a bearish move.";
            break;
         case MODE_ADVANCED:
            liqLine = "Buy-side liquidity swept. Stop-hunt complete. Potential bearish continuation.";
            break;
         case MODE_INSTITUTIONAL:
            liqLine = "Buy-side liquidity pool consumed. Market makers have offloaded longs "
                      "and may now drive price lower. Watch for bearish displacement post-sweep.";
            break;
      }
   }
   else if(ctx.nLiq > 0)
   {
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            liqLine = "There are groups of stop losses resting above and/or below current price. "
                      "Price often moves toward these before reversing.";
            break;
         case MODE_ADVANCED:
            liqLine = "Unswept liquidity pools present. Market may engineer a move to collect "
                      "these stops before committing to directional bias.";
            break;
         case MODE_INSTITUTIONAL:
            liqLine = "Untapped liquidity pools identified. Institutional players need this "
                      "liquidity to fill large orders — expect a manipulation spike before trend.";
            break;
      }
   }
   if(liqLine != "") { n = ArraySize(lines); ArrayResize(lines, n + 1); lines[n] = liqLine; }

   // ─── Line 4: Phase + Imbalance ────────────────────────────────
   string phaseLine = "";
   string phase = PhaseWord(ctx.phase);

   if(ctx.phase == PHASE_EXPANSION)
   {
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            phaseLine = "Price is in a strong expansion phase — momentum is healthy and directional.";
            break;
         case MODE_ADVANCED:
            phaseLine = "Expansion phase: ATR broadening, consecutive BOS events. "
                        "Ride momentum; avoid fading.";
            break;
         case MODE_INSTITUTIONAL:
            phaseLine = "Expansion phase: order flow imbalance driving displacement. "
                        "First pullback OB is highest-probability continuation entry.";
            break;
      }
   }
   else if(ctx.phase == PHASE_COMPRESSION)
   {
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            phaseLine = "Price is coiling tightly. A big move is likely building — "
                        "watch for a breakout.";
            break;
         case MODE_ADVANCED:
            phaseLine = "Compression phase: ATR contracting. Pre-breakout consolidation. "
                        "Look for liquidity sweep before expansion begins.";
            break;
         case MODE_INSTITUTIONAL:
            phaseLine = "Compression: institutions coiling the spring. A stop-hunt of range "
                        "extremes (manipulation) typically precedes the real expansion.";
            break;
      }
   }
   else if(ctx.phase == PHASE_CORRECTIVE)
   {
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            phaseLine = "Price is in a pullback — this is normal within a trend. "
                        "Wait for the pullback to end before entering.";
            break;
         case MODE_ADVANCED:
            phaseLine = "Corrective phase: overlapping candles, declining ATR. "
                        "Watch for OB/FVG reaction to signal end of correction.";
            break;
         case MODE_INSTITUTIONAL:
            phaseLine = "Corrective phase: smart money allowing weak hands to enter "
                        "against the trend. OB or FVG reaction will signal resumption of institutional flow.";
            break;
      }
   }
   else if(ctx.phase == PHASE_ACCUMULATION)
   {
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            phaseLine = "Market is ranging with low volatility — possibly building for a big move.";
            break;
         case MODE_ADVANCED:
            phaseLine = "Accumulation: low ATR, tight range. Smart money potentially loading "
                        "positions. No high-probability entries until direction confirmed.";
            break;
         case MODE_INSTITUTIONAL:
            phaseLine = "Accumulation phase: composite operator distributing positions within a "
                        "defined range. Expect manipulation before directional commitment.";
            break;
      }
   }

   if(phaseLine != "") { n = ArraySize(lines); ArrayResize(lines, n + 1); lines[n] = phaseLine; }

   // ─── Line 5: Imbalance / Zone ─────────────────────────────────
   string zoneLine = "";
   if(ctx.hasBullOB && !ctx.hasBearOB && ctx.trend == TREND_BULLISH)
   {
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            zoneLine = "A bullish order block is present — this is a zone where big buyers entered.";
            break;
         case MODE_ADVANCED:
            zoneLine = "Bullish OB aligns with trend. If price returns here, it's a "
                       "high-probability long entry zone.";
            break;
         case MODE_INSTITUTIONAL:
            zoneLine = "Bullish OB: institutional footprint from the last bearish candle "
                       "before displacement. Premium zone for buy orders on retracement.";
            break;
      }
   }
   else if(ctx.hasBearOB && !ctx.hasBullOB && ctx.trend == TREND_BEARISH)
   {
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            zoneLine = "A bearish order block is present — this is where big sellers entered.";
            break;
         case MODE_ADVANCED:
            zoneLine = "Bearish OB aligns with trend. If price rallies here, "
                       "it's a high-probability short entry zone.";
            break;
         case MODE_INSTITUTIONAL:
            zoneLine = "Bearish OB: institutional sell footprint. Last bullish candle before "
                       "displacement. Discount zone for sell orders on retracement.";
            break;
      }
   }
   if(ctx.hasBullFVG || ctx.hasBearFVG)
   {
      if(zoneLine != "") zoneLine += " ";
      switch(ctx.mode)
      {
         case MODE_BEGINNER:    zoneLine += "Price gap (imbalance) detected — price may return to fill it."; break;
         case MODE_ADVANCED:    zoneLine += "FVG present: market left an inefficiency that may act as a magnet."; break;
         case MODE_INSTITUTIONAL: zoneLine += "FVG: institutional order flow imbalance. Price statistically returns to 50% of gap."; break;
      }
   }
   if(zoneLine != "") { n = ArraySize(lines); ArrayResize(lines, n + 1); lines[n] = zoneLine; }

   // ─── HTF Divergence Warning ────────────────────────────────────
   if(ctx.htfTrend != TREND_UNDEFINED && ctx.htfTrend != ctx.trend &&
      ctx.trend != TREND_RANGING)
   {
      string divLine = "";
      switch(ctx.mode)
      {
         case MODE_BEGINNER:
            divLine = "Caution: this move goes AGAINST the higher timeframe trend. "
                      "Counter-trend moves are riskier.";
            break;
         case MODE_ADVANCED:
            divLine = "HTF divergence: current " + TrendWord(ctx.trend) +
                      " move is counter to " + EnumToString(ctx.htf) +
                      " " + TrendWord(ctx.htfTrend) + " bias.";
            break;
         case MODE_INSTITUTIONAL:
            divLine = "Counter-trend move on HTF: possible induced liquidity grab "
                      "before resumption of " + TrendWord(ctx.htfTrend) + " flow. "
                      "Manage exposure carefully.";
            break;
      }
      n = ArraySize(lines); ArrayResize(lines, n + 1); lines[n] = divLine;
   }

   // ─── Assemble narrative ───────────────────────────────────────
   ctx.narrative = "";
   for(int i = 0; i < ArraySize(lines); i++)
   {
      if(lines[i] == "") continue;
      ctx.narrative += (i > 0 ? " | " : "") + lines[i];
   }
}

#endif // PAM_SCORING_MQH
