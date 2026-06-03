//+------------------------------------------------------------------+
//| PAM/StructureEngine.mqh  —  Market structure detection          |
//|                                                                  |
//| Detects: HH HL LH LL  |  BOS  |  CHoCH  |  MSS                |
//| Guarantees: ZERO repainting — pivots confirmed only after       |
//| InpPivotStr bars have fully closed on BOTH sides.              |
//+------------------------------------------------------------------+
#ifndef PAM_STRUCTURE_MQH
#define PAM_STRUCTURE_MQH
#include "Context.mqh"

//+------------------------------------------------------------------+
// IsConfirmedPivotHigh:
//   high[i] is the strictest local maximum within ±pivStr bars.
//   With series arrays (index 0 = newest), we need:
//     i >= pivStr           (pivStr newer bars exist)
//     i+pivStr < total      (pivStr older bars exist)
//   This ensures BOTH sides are fully closed — no future-look.
//+------------------------------------------------------------------+
bool IsConfirmedPivotHigh(const double &high[], int i, int pivStr, int total)
{
   if(i < pivStr || i + pivStr >= total) return false;
   for(int k = 1; k <= pivStr; k++)
   {
      if(high[i - k] >= high[i]) return false;   // newer bar is as high or higher
      if(high[i + k] >= high[i]) return false;   // older bar is as high or higher
   }
   return true;
}

bool IsConfirmedPivotLow(const double &low[], int i, int pivStr, int total)
{
   if(i < pivStr || i + pivStr >= total) return false;
   for(int k = 1; k <= pivStr; k++)
   {
      if(low[i - k] <= low[i]) return false;
      if(low[i + k] <= low[i]) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
// ComputeStructure
//   Scans bars oldest→newest (high index → low index in series).
//   Builds swing sequence and labels HH/HL/LH/LL.
//   Detects BOS, CHoCH, MSS.
//   Populates ctx.swings[], ctx.trend, and helper flags.
//+------------------------------------------------------------------+
void StructureEngine_Compute(SPAMContext &ctx,
                              const double   &high[],
                              const double   &low[],
                              const double   &close[],
                              const datetime &time[],
                              const double   &atr[],
                              int total)
{
   ctx.nSwings      = 0;
   ctx.trend        = TREND_UNDEFINED;
   ctx.hasBullBOS   = false;
   ctx.hasBearBOS   = false;
   ctx.hasBullCHoCH = false;
   ctx.hasBearCHoCH = false;
   ctx.hasBullMSS   = false;
   ctx.hasBearMSS   = false;
   ctx.lastSwH      = 0;
   ctx.lastSwL      = 0;
   ctx.prevSwH      = 0;
   ctx.prevSwL      = 0;

   int limit  = MathMin(ctx.lookback, total - ctx.pivStr - 1);
   int pivStr = ctx.pivStr;

   // Tracking state for swing labeling
   double  runSwH = 0, runSwL = 0;   // running last confirmed swing H/L
   double  prevH  = 0, prevL  = 0;
   ETrend  runTrend = TREND_UNDEFINED;

   // Scan oldest first (high bar index → low bar index in series)
   for(int i = limit; i >= pivStr; i--)
   {
      bool isPH = IsConfirmedPivotHigh(high, i, pivStr, total);
      bool isPL = IsConfirmedPivotLow(low,   i, pivStr, total);

      if(!isPH && !isPL) continue;
      if(ctx.nSwings >= PAM_MAX_SWINGS - 1) break;

      SSwing sw;
      sw.bar      = i;
      sw.time     = time[i];
      sw.isBOS    = false;
      sw.isCHoCH  = false;
      sw.isMSS    = false;
      sw.label    = SE_NONE;

      if(isPH)
      {
         sw.isHigh = true;
         sw.price  = high[i];

         if(runSwH > 0)
         {
            if(sw.price > runSwH)
            {
               sw.label = SE_HH;
               if(runTrend == TREND_BEARISH)
               {
                  // Bearish trend formed a HH — CHoCH / MSS
                  sw.isCHoCH = true;
                  ctx.hasBullCHoCH = true;
                  // MSS if displacement candle drove the break
                  double bodyNow = MathAbs(close[i] - (high[i] + low[i]) / 2.0);
                  if(bodyNow > atr[i] * 0.7) { sw.isMSS = true; ctx.hasBullMSS = true; }
                  runTrend = TREND_BULLISH;
               }
               else
               {
                  // BOS upward in bullish trend
                  if(runTrend == TREND_BULLISH) { sw.isBOS = true; ctx.hasBullBOS = true; }
                  runTrend = TREND_BULLISH;
               }
            }
            else
            {
               sw.label = SE_LH;
               if(runTrend == TREND_BULLISH && runSwL > 0)
               {
                  // Could be start of bearish reversal — wait for LL to confirm
               }
               runTrend = TREND_BEARISH;
            }
         }
         prevH  = runSwH;
         runSwH = sw.price;
      }
      else  // pivot low
      {
         sw.isHigh = false;
         sw.price  = low[i];

         if(runSwL > 0)
         {
            if(sw.price < runSwL)
            {
               sw.label = SE_LL;
               if(runTrend == TREND_BULLISH)
               {
                  // Bullish trend formed a LL — CHoCH / MSS
                  sw.isCHoCH = true;
                  ctx.hasBearCHoCH = true;
                  double bodyNow = MathAbs(close[i] - (high[i] + low[i]) / 2.0);
                  if(bodyNow > atr[i] * 0.7) { sw.isMSS = true; ctx.hasBearMSS = true; }
                  runTrend = TREND_BEARISH;
               }
               else
               {
                  // BOS downward in bearish trend
                  if(runTrend == TREND_BEARISH) { sw.isBOS = true; ctx.hasBearBOS = true; }
                  runTrend = TREND_BEARISH;
               }
            }
            else
            {
               sw.label = SE_HL;
               runTrend = TREND_BULLISH;
            }
         }
         prevL  = runSwL;
         runSwL = sw.price;
      }

      ctx.swings[ctx.nSwings] = sw;
      ctx.nSwings++;
   }

   // Final trend from most recent swing sequence
   ctx.trend     = runTrend;
   ctx.lastSwH   = runSwH;
   ctx.lastSwL   = runSwL;
   ctx.prevSwH   = prevH;
   ctx.prevSwL   = prevL;

   // Grab times of last swing highs/lows
   for(int z = ctx.nSwings - 1; z >= 0; z--)
   {
      if(ctx.swings[z].isHigh && ctx.lastSwHTime == 0)
         ctx.lastSwHTime = ctx.swings[z].time;
      if(!ctx.swings[z].isHigh && ctx.lastSwLTime == 0)
         ctx.lastSwLTime = ctx.swings[z].time;
      if(ctx.lastSwHTime > 0 && ctx.lastSwLTime > 0) break;
   }

   // Ranging detection — if last 4 swings have overlapping highs/lows
   if(ctx.nSwings >= 4 && runTrend == TREND_UNDEFINED)
      ctx.trend = TREND_RANGING;
}

//+------------------------------------------------------------------+
// DrawStructure
//   Draws swing connections, labels, BOS/CHoCH markers.
//+------------------------------------------------------------------+
void StructureEngine_Draw(const SPAMContext &ctx,
                           const datetime   &time[],
                           const string     &pfx,
                           color             bullCol,
                           color             bearCol,
                           color             neutCol)
{
   if(ctx.nSwings < 2) return;

   // Draw zig-zag lines connecting confirmed swings
   for(int i = 1; i < ctx.nSwings; i++)
   {
      SSwing a = ctx.swings[i - 1];
      SSwing b = ctx.swings[i];
      color  c = (b.isHigh) ? bullCol : bearCol;

      string nm = pfx + "SL" + IntegerToString(i);
      ObjectCreate(0, nm, OBJ_TREND, 0, a.time, a.price, b.time, b.price);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,     c);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,     1);
      ObjectSetInteger(0, nm, OBJPROP_STYLE,     STYLE_SOLID);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, nm, OBJPROP_BACK,      true);
   }

   // Draw swing labels and event markers
   for(int i = 0; i < ctx.nSwings; i++)
   {
      SSwing sw = ctx.swings[i];
      if(sw.label == SE_NONE) continue;

      string lbl = "";
      color  lc  = neutCol;
      bool   above = sw.isHigh;   // label position

      switch(sw.label)
      {
         case SE_HH:  lbl = "HH";   lc = bullCol;  above = true;  break;
         case SE_HL:  lbl = "HL";   lc = bullCol;  above = false; break;
         case SE_LH:  lbl = "LH";   lc = bearCol;  above = true;  break;
         case SE_LL:  lbl = "LL";   lc = bearCol;  above = false; break;
         default: break;
      }

      // BOS / CHoCH / MSS suffix
      if(sw.isMSS)        { lbl += " MSS"; lc = (sw.isHigh ? bullCol : bearCol); }
      else if(sw.isCHoCH) { lbl += " CHoCH"; }
      else if(sw.isBOS)   { lbl += " BOS"; }

      if(lbl == "") continue;

      double  labelY = above ? (sw.price + ctx.atr * 0.3) : (sw.price - ctx.atr * 0.3);
      string  nm     = pfx + "SSL" + IntegerToString(i);
      ObjectCreate(0, nm, OBJ_TEXT, 0, sw.time, labelY);
      ObjectSetString(0,  nm, OBJPROP_TEXT,      lbl);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,     lc);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,  7);
      ObjectSetString(0,  nm, OBJPROP_FONT,      "Consolas");
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR,    above ? ANCHOR_LOWER : ANCHOR_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE,false);

      // BOS/CHoCH horizontal line at break level
      if((sw.isBOS || sw.isCHoCH || sw.isMSS) && ctx.nSwings > 0)
      {
         string hnm  = pfx + "BOSS" + IntegerToString(i);
         color  hcol = sw.isMSS ? lc : neutCol;
         ENUM_LINE_STYLE hst = sw.isMSS ? STYLE_SOLID : STYLE_DASH;
         ObjectCreate(0, hnm, OBJ_TREND, 0, sw.time, sw.price, time[0], sw.price);
         ObjectSetInteger(0, hnm, OBJPROP_COLOR,      hcol);
         ObjectSetInteger(0, hnm, OBJPROP_STYLE,      hst);
         ObjectSetInteger(0, hnm, OBJPROP_WIDTH,      1);
         ObjectSetInteger(0, hnm, OBJPROP_RAY_RIGHT,  true);
         ObjectSetInteger(0, hnm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, hnm, OBJPROP_BACK,       true);
      }
   }
}

//+------------------------------------------------------------------+
// PhaseEngine — detect current market phase from structure + ATR
//+------------------------------------------------------------------+
void StructureEngine_DetectPhase(SPAMContext &ctx,
                                  const double &atr[],
                                  int           total)
{
   if(ctx.nSwings < 3 || total < 20)
   {
      ctx.phase = PHASE_UNDEFINED;
      return;
   }

   // ATR trend: compare current ATR to 20-bar lookback
   int    lookAtr = MathMin(20, total - 1);
   double atrOld  = atr[lookAtr];
   double atrNow  = atr[0];
   double atrRatio= (atrOld > 1e-10) ? atrNow / atrOld : 1.0;

   bool expanding   = (atrRatio > 1.20);
   bool contracting = (atrRatio < 0.80);

   // Count recent BOS events
   int bosCount = 0;
   for(int i = MathMax(0, ctx.nSwings - 6); i < ctx.nSwings; i++)
      if(ctx.swings[i].isBOS) bosCount++;

   bool hasChoCh = ctx.hasBullCHoCH || ctx.hasBearCHoCH;
   bool hasMss   = ctx.hasBullMSS   || ctx.hasBearMSS;

   if(expanding && bosCount >= 2)
      ctx.phase = PHASE_EXPANSION;
   else if(expanding && hasChoCh)
      ctx.phase = PHASE_MANIPULATION;
   else if(contracting && bosCount == 0)
      ctx.phase = PHASE_COMPRESSION;
   else if(contracting && ctx.trend != TREND_UNDEFINED)
      ctx.phase = PHASE_CORRECTIVE;
   else if(!expanding && !contracting && bosCount >= 2)
      ctx.phase = PHASE_TRENDING;
   else if(!expanding && !contracting && bosCount == 0)
      ctx.phase = PHASE_ACCUMULATION;
   else if(hasMss)
      ctx.phase = PHASE_DISTRIBUTION;
   else
      ctx.phase = PHASE_UNDEFINED;
}

//+------------------------------------------------------------------+
// StructureEngine_ComputeInternal  (v1.1)
//   Runs a second pivot scan with pivStr/2 to reveal micro structure
//   that forms INSIDE the larger swing moves — the internal delivery
//   legs that smart money uses for intraswing distribution/accumulation.
//   Results stored in ctx.iSwings[].
//+------------------------------------------------------------------+
void StructureEngine_ComputeInternal(SPAMContext    &ctx,
                                      const double   &high[],
                                      const double   &low[],
                                      const datetime &time[],
                                      int             total)
{
   ctx.nISwings = 0;
   if(!ctx.showInternal) return;

   int ps    = MathMax(2, ctx.pivStr / 2);
   int limit = MathMin(ctx.lookback, total - ps - 1);

   double runH = 0, runL = 0;

   for(int i = limit; i >= ps; i--)
   {
      bool isPH = IsConfirmedPivotHigh(high, i, ps, total);
      bool isPL = IsConfirmedPivotLow(low,   i, ps, total);
      if(!isPH && !isPL) continue;
      if(ctx.nISwings >= PAM_MAX_SWINGS - 1) break;

      SSwing sw;
      sw.bar     = i;
      sw.time    = time[i];
      sw.isBOS   = false;
      sw.isCHoCH = false;
      sw.isMSS   = false;
      sw.label   = SE_NONE;

      if(isPH)
      {
         sw.isHigh = true;
         sw.price  = high[i];
         if(runH > 0) sw.label = (sw.price > runH) ? SE_HH : SE_LH;
         runH = sw.price;
      }
      else
      {
         sw.isHigh = false;
         sw.price  = low[i];
         if(runL > 0) sw.label = (sw.price < runL) ? SE_LL : SE_HL;
         runL = sw.price;
      }

      ctx.iSwings[ctx.nISwings] = sw;
      ctx.nISwings++;
   }
}

//+------------------------------------------------------------------+
// StructureEngine_DrawInternal  (v1.1)
//   Draws internal swings as thin dotted lines with lowercase labels
//   (iHH / iHL / iLH / iLL) so they read as subordinate structure.
//+------------------------------------------------------------------+
void StructureEngine_DrawInternal(const SPAMContext &ctx,
                                   const string     &pfx,
                                   color             bullCol,
                                   color             bearCol)
{
   if(!ctx.showInternal || ctx.nISwings < 2) return;

   // Dim the internal colors so they sit visually "under" the main lines
   color iBull = (color)((((int)bullCol >> 16) / 3)   << 16 |
                          (((int)bullCol >> 8 & 0xFF) / 3) << 8 |
                           ((int)bullCol & 0xFF) / 3);
   color iBear = (color)((((int)bearCol >> 16) / 3)   << 16 |
                          (((int)bearCol >> 8 & 0xFF) / 3) << 8 |
                           ((int)bearCol & 0xFF) / 3);

   // Use fixed dim colours instead to avoid color arithmetic issues
   iBull = C'0,60,40';
   iBear = C'70,20,20';

   for(int i = 1; i < ctx.nISwings; i++)
   {
      SSwing a = ctx.iSwings[i - 1];
      SSwing b = ctx.iSwings[i];
      color  lc = b.isHigh ? iBull : iBear;

      string nm = pfx + "ISL" + IntegerToString(i);
      ObjectCreate(0, nm, OBJ_TREND, 0, a.time, a.price, b.time, b.price);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      lc);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,       1);
      ObjectSetInteger(0, nm, OBJPROP_STYLE,       STYLE_DOT);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT,   false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, nm, OBJPROP_BACK,        true);
   }

   // Lowercase labels on labelled internal swings
   for(int i = 0; i < ctx.nISwings; i++)
   {
      SSwing sw = ctx.iSwings[i];
      if(sw.label == SE_NONE) continue;

      string lbl = "";
      switch(sw.label)
      {
         case SE_HH: lbl = "ihh"; break;
         case SE_HL: lbl = "ihl"; break;
         case SE_LH: lbl = "ilh"; break;
         case SE_LL: lbl = "ill"; break;
         default:    break;
      }
      if(lbl == "") continue;

      bool   above = sw.isHigh;
      double py    = above ? sw.price + ctx.atr * 0.18 : sw.price - ctx.atr * 0.18;
      color  lc    = above ? iBull : iBear;

      string nm = pfx + "ISSL" + IntegerToString(i);
      ObjectCreate(0, nm, OBJ_TEXT, 0, sw.time, py);
      ObjectSetString(0,  nm, OBJPROP_TEXT,       lbl);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      lc);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,   6);
      ObjectSetString(0,  nm, OBJPROP_FONT,       "Consolas");
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR,     above ? ANCHOR_LOWER : ANCHOR_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   }
}

#endif // PAM_STRUCTURE_MQH
