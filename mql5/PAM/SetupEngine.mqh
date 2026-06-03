//+------------------------------------------------------------------+
//| PAM/SetupEngine.mqh  —  Setup Pattern Markers  (v1.4)           |
//|                                                                  |
//| Detects and marks four institutional entry patterns:            |
//|                                                                  |
//| JUDAS SWING   — Within a kill zone, price pierces a key level   |
//|                 (PDH / PDL / lastSwH / lastSwL) on a wick but   |
//|                 closes back inside. Institutions engineered a    |
//|                 stop-hunt to collect liquidity before revealing  |
//|                 true direction. Marked "JS↑" / "JS↓" on bar.   |
//|                                                                  |
//| SILVER BULLET — 1-hour windows (10-11 AM, 2-3 PM NY-equivalent) |
//|                 where FVG + BOS combinations carry the highest   |
//|                 statistical resolution for the day's range.      |
//|                 Draws shaded "SB" box over the window.           |
//|                                                                  |
//| CISD          — Change in State of Delivery. Two candles in one  |
//|                 direction followed by a strong reversal candle   |
//|                 (body > 55%) signals that the delivery mechanism  |
//|                 has flipped. Marked "⟳↑" / "⟳↓" on bar.        |
//|                                                                  |
//| OTE           — Optimal Trade Entry. Price in the 61.8–78.6%    |
//|                 Fibonacci retracement zone of the last swing,   |
//|                 confirmed by an overlapping OB or FVG. Highest- |
//|                 probability ICT entry model. Shown as a zone box.|
//+------------------------------------------------------------------+
#ifndef PAM_SETUP_MQH
#define PAM_SETUP_MQH
#include "Context.mqh"

//--- Check if hour falls in any standard KZ window (for Judas detection,
//    independent of user's KZ display toggles).
//    GetKillZone and EKillZone are defined in KillZoneEngine.mqh,
//    which is included before this file.
bool InAnyKZ(int hour)
{
   return GetKillZone(hour, true, true, true, true) != KZ_NONE;
}

//+------------------------------------------------------------------+
// SetupEngine_Compute
//   Evaluates current bar conditions and recent history to set
//   ctx.activeSetup — used by the dashboard SETUP row.
//   Priority: OTE → CISD → Judas Swing.
//+------------------------------------------------------------------+
void SetupEngine_Compute(SPAMContext     &ctx,
                          const double   &open[],
                          const double   &high[],
                          const double   &low[],
                          const double   &close[],
                          const datetime &time[],
                          int             total)
{
   ctx.activeSetup = "";

   // ─── OTE Zone (current bar) ───────────────────────────────────
   if(ctx.showOTE && ctx.equilPrice > 0 && ctx.lastSwH > ctx.lastSwL)
   {
      // Bull OTE: bullish trend, price retraced to 61.8–78.6% FROM the swing high
      // premDiscPct is 0=SwL, 100=SwH, so 61.8-78.6% from top = 21.4-38.2% from bottom
      bool oteBull = (ctx.trend == TREND_BULLISH &&
                      ctx.premDiscPct >= 21.4 && ctx.premDiscPct <= 38.2 &&
                      (ctx.hasBullOB || ctx.hasBullFVG));

      // Bear OTE: bearish trend, price bounced to 61.8–78.6% from swing low
      bool oteBear = (ctx.trend == TREND_BEARISH &&
                      ctx.premDiscPct >= 61.8 && ctx.premDiscPct <= 78.6 &&
                      (ctx.hasBearOB || ctx.hasBearFVG));

      if(oteBull)      ctx.activeSetup = "OTE ↑  61.8-78.6% + OB/FVG";
      else if(oteBear) ctx.activeSetup = "OTE ↓  61.8-78.6% + OB/FVG";
   }

   // ─── CISD (recent bars — overwrites if within last 3 bars) ────
   if(ctx.showCISD)
   {
      int scanLimit = MathMin(10, total - 3);
      for(int i = 1; i <= scanLimit; i++)
      {
         if(i + 2 >= total) break;
         double body  = MathAbs(close[i] - open[i]);
         double range = high[i] - low[i];
         if(range < 1e-10) continue;

         bool prev2Bear = close[i+2] < open[i+2];
         bool prev1Bear = close[i+1] < open[i+1];
         bool currBull  = close[i]   > open[i];
         bool prev2Bull = close[i+2] > open[i+2];
         bool prev1Bull = close[i+1] > open[i+1];
         bool currBear  = close[i]   < open[i];

         bool cisdBull = prev2Bear && prev1Bear && currBull && (body / range > 0.55);
         bool cisdBear = prev2Bull && prev1Bull && currBear && (body / range > 0.55);

         if((cisdBull || cisdBear) && i <= 3)
         {
            ctx.activeSetup = cisdBull
               ? "CISD ↑  delivery shifted bullish"
               : "CISD ↓  delivery shifted bearish";
            break;
         }
         if(cisdBull || cisdBear) break;
      }
   }

   // ─── Judas Swing (recent KZ bars — overwrites if within 5 bars)
   if(ctx.showJudas)
   {
      int scanLimit = MathMin(20, total - 2);
      for(int i = 1; i <= scanLimit; i++)
      {
         MqlDateTime dt;
         TimeToStruct(time[i], dt);
         if(!InAnyKZ(dt.hour)) continue;

         bool judasBear = (ctx.pdHigh  > 0 && high[i] > ctx.pdHigh  && close[i] < ctx.pdHigh)  ||
                          (ctx.lastSwH > 0 && high[i] > ctx.lastSwH && close[i] < ctx.lastSwH);
         bool judasBull = (ctx.pdLow   > 0 && low[i]  < ctx.pdLow   && close[i] > ctx.pdLow)   ||
                          (ctx.lastSwL > 0 && low[i]  < ctx.lastSwL && close[i] > ctx.lastSwL);

         if(i <= 5)
         {
            if(judasBear) { ctx.activeSetup = "Judas ↓  KZ stop-hunt above key high"; break; }
            if(judasBull) { ctx.activeSetup = "Judas ↑  KZ stop-hunt below key low";  break; }
         }
         else if(judasBear || judasBull) break;
      }
   }
}

//+------------------------------------------------------------------+
// SetupEngine_Draw
//   Renders all setup markers on the chart. Called once per new bar.
//+------------------------------------------------------------------+
void SetupEngine_Draw(const SPAMContext &ctx,
                       const datetime   &time[],
                       const double     &open[],
                       const double     &high[],
                       const double     &low[],
                       const double     &close[],
                       int               total,
                       const string     &pfx)
{
   int limit = MathMin(ctx.lookback, total - 1);

   // ─── Silver Bullet windows ───────────────────────────────────
   if(ctx.showSilverBullet)
   {
      for(int pass = 0; pass < 2; pass++)
      {
         int winOpen  = (pass == 0) ? ctx.sbAMOpenH  : ctx.sbPMOpenH;
         int winClose = (pass == 0) ? ctx.sbAMCloseH : ctx.sbPMCloseH;
         string tag   = (pass == 0) ? "SBAM" : "SBPM";
         color borderCol = C'160,80,220';
         color fillCol   = C'16,6,26';

         bool     inWin   = false;
         double   segH    = -DBL_MAX, segL = DBL_MAX;
         datetime segS    = 0, segE = 0;
         int      boxCnt  = 0;
         int      maxBoxes = ctx.kzDays * 3;

         for(int i = limit; i >= 0; i--)
         {
            MqlDateTime dt;
            TimeToStruct(time[i], dt);
            bool inside = (dt.hour >= winOpen && dt.hour < winClose);

            if(inside)
            {
               if(!inWin) { segS = time[i]; segH = -DBL_MAX; segL = DBL_MAX; }
               inWin = true;
               segH  = MathMax(segH, high[i]);
               segL  = MathMin(segL, low[i]);
               segE  = time[i];
            }
            else if(inWin)
            {
               if(boxCnt < maxBoxes && segH > segL)
               {
                  string nm  = pfx + tag + IntegerToString((int)segS);
                  string lnm = pfx + tag + "L" + IntegerToString((int)segS);

                  ObjectCreate(0, nm, OBJ_RECTANGLE, 0, segS, segH, segE, segL);
                  ObjectSetInteger(0, nm, OBJPROP_COLOR,      borderCol);
                  ObjectSetInteger(0, nm, OBJPROP_STYLE,      ctx.outlineMode ? STYLE_DOT : STYLE_SOLID);
                  ObjectSetInteger(0, nm, OBJPROP_WIDTH,      1);
                  ObjectSetInteger(0, nm, OBJPROP_FILL,       !ctx.outlineMode);
                  ObjectSetInteger(0, nm, OBJPROP_BGCOLOR,    fillCol);
                  ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
                  ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);

                  ObjectCreate(0, lnm, OBJ_TEXT, 0, segS, segH);
                  ObjectSetString(0,  lnm, OBJPROP_TEXT,      "SB");
                  ObjectSetInteger(0, lnm, OBJPROP_COLOR,     borderCol);
                  ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE,  6);
                  ObjectSetString(0,  lnm, OBJPROP_FONT,      "Consolas");
                  ObjectSetInteger(0, lnm, OBJPROP_ANCHOR,    ANCHOR_LOWER);
                  ObjectSetInteger(0, lnm, OBJPROP_BACK,      true);
                  ObjectSetInteger(0, lnm, OBJPROP_SELECTABLE,false);
                  boxCnt++;
               }
               inWin = false;
            }
         }
         // Flush final open window
         if(inWin && boxCnt < maxBoxes && segH > segL)
         {
            string nm  = pfx + tag + IntegerToString((int)segS);
            string lnm = pfx + tag + "L" + IntegerToString((int)segS);
            ObjectCreate(0, nm, OBJ_RECTANGLE, 0, segS, segH, segE, segL);
            ObjectSetInteger(0, nm, OBJPROP_COLOR,      borderCol);
            ObjectSetInteger(0, nm, OBJPROP_STYLE,      ctx.outlineMode ? STYLE_DOT : STYLE_SOLID);
            ObjectSetInteger(0, nm, OBJPROP_WIDTH,      1);
            ObjectSetInteger(0, nm, OBJPROP_FILL,       !ctx.outlineMode);
            ObjectSetInteger(0, nm, OBJPROP_BGCOLOR,    fillCol);
            ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
            ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
            ObjectCreate(0, lnm, OBJ_TEXT, 0, segS, segH);
            ObjectSetString(0,  lnm, OBJPROP_TEXT,      "SB");
            ObjectSetInteger(0, lnm, OBJPROP_COLOR,     borderCol);
            ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE,  6);
            ObjectSetString(0,  lnm, OBJPROP_FONT,      "Consolas");
            ObjectSetInteger(0, lnm, OBJPROP_ANCHOR,    ANCHOR_LOWER);
            ObjectSetInteger(0, lnm, OBJPROP_BACK,      true);
            ObjectSetInteger(0, lnm, OBJPROP_SELECTABLE,false);
         }
      }
   }

   // ─── Judas Swing labels ──────────────────────────────────────
   if(ctx.showJudas)
   {
      int scanLimit = MathMin(limit, total - 2);
      int cnt = 0;
      for(int i = 1; i <= scanLimit && cnt < 12; i++)
      {
         MqlDateTime dt;
         TimeToStruct(time[i], dt);
         if(!InAnyKZ(dt.hour)) continue;

         bool judasBear = (ctx.pdHigh  > 0 && high[i] > ctx.pdHigh  && close[i] < ctx.pdHigh)  ||
                          (ctx.lastSwH > 0 && high[i] > ctx.lastSwH && close[i] < ctx.lastSwH);
         bool judasBull = (ctx.pdLow   > 0 && low[i]  < ctx.pdLow   && close[i] > ctx.pdLow)   ||
                          (ctx.lastSwL > 0 && low[i]  < ctx.lastSwL && close[i] > ctx.lastSwL);

         if(!judasBear && !judasBull) continue;

         string nm    = pfx + "JS" + IntegerToString(i);
         string label = judasBear ? "JS↓" : "JS↑";
         color  col   = judasBear ? C'255,80,80' : C'80,220,150';
         double aPrice = judasBear ? high[i] : low[i];
         int    anc    = judasBear ? ANCHOR_LOWER : ANCHOR_UPPER;

         ObjectCreate(0, nm, OBJ_TEXT, 0, time[i], aPrice);
         ObjectSetString(0,  nm, OBJPROP_TEXT,      label);
         ObjectSetInteger(0, nm, OBJPROP_COLOR,     col);
         ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,  7);
         ObjectSetString(0,  nm, OBJPROP_FONT,      "Consolas");
         ObjectSetInteger(0, nm, OBJPROP_ANCHOR,    anc);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0, nm, OBJPROP_BACK,      false);
         cnt++;
      }
   }

   // ─── CISD delivery-shift markers ─────────────────────────────
   if(ctx.showCISD)
   {
      int scanLimit = MathMin(limit, total - 3);
      int cnt = 0;
      for(int i = 1; i <= scanLimit && cnt < 20; i++)
      {
         if(i + 2 >= total) break;
         double body  = MathAbs(close[i] - open[i]);
         double range = high[i] - low[i];
         if(range < 1e-10) continue;

         bool prev2Bear = close[i+2] < open[i+2];
         bool prev1Bear = close[i+1] < open[i+1];
         bool currBull  = close[i]   > open[i];
         bool prev2Bull = close[i+2] > open[i+2];
         bool prev1Bull = close[i+1] > open[i+1];
         bool currBear  = close[i]   < open[i];

         bool cisdBull = prev2Bear && prev1Bear && currBull && (body / range > 0.55);
         bool cisdBear = prev2Bull && prev1Bull && currBear && (body / range > 0.55);

         if(!cisdBull && !cisdBear) continue;

         string nm    = pfx + "CISD" + IntegerToString(i);
         string label = cisdBull ? "SD↑" : "SD↓";
         color  col   = cisdBull ? C'0,220,140' : C'220,80,80';
         double aPrice = cisdBull ? low[i] : high[i];
         int    anc    = cisdBull ? ANCHOR_UPPER : ANCHOR_LOWER;

         ObjectCreate(0, nm, OBJ_TEXT, 0, time[i], aPrice);
         ObjectSetString(0,  nm, OBJPROP_TEXT,      label);
         ObjectSetInteger(0, nm, OBJPROP_COLOR,     col);
         ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,  7);
         ObjectSetString(0,  nm, OBJPROP_FONT,      "Consolas");
         ObjectSetInteger(0, nm, OBJPROP_ANCHOR,    anc);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0, nm, OBJPROP_BACK,      false);
         cnt++;
      }
   }

   // ─── OTE zone rectangle ──────────────────────────────────────
   if(ctx.showOTE && ctx.lastSwH > ctx.lastSwL)
   {
      double range = ctx.lastSwH - ctx.lastSwL;
      if(range > 1e-10)
      {
         double oteHi  = 0, oteLo = 0;
         color  fillCol = 0, brdCol = 0;
         bool   drawIt  = false;

         if(ctx.trend == TREND_BULLISH)
         {
            // Bull OTE: 61.8-78.6% from TOP = 21.4-38.2% from bottom
            oteLo   = ctx.lastSwL + range * 0.214;
            oteHi   = ctx.lastSwL + range * 0.382;
            fillCol = C'0,22,14';
            brdCol  = C'0,160,90';
            drawIt  = ctx.hasBullOB || ctx.hasBullFVG;
         }
         else if(ctx.trend == TREND_BEARISH)
         {
            // Bear OTE: 61.8-78.6% from bottom
            oteLo   = ctx.lastSwL + range * 0.618;
            oteHi   = ctx.lastSwL + range * 0.786;
            fillCol = C'22,0,0';
            brdCol  = C'160,50,50';
            drawIt  = ctx.hasBearOB || ctx.hasBearFVG;
         }

         if(drawIt && oteHi > oteLo)
         {
            int      lb = MathMin(ctx.lookback, total - 1);
            datetime lt = time[lb];
            datetime rt = time[0];

            string nm  = pfx + "OTE";
            string lnm = pfx + "OTEL";

            ObjectCreate(0, nm, OBJ_RECTANGLE, 0, lt, oteHi, rt, oteLo);
            ObjectSetInteger(0, nm, OBJPROP_COLOR,      brdCol);
            ObjectSetInteger(0, nm, OBJPROP_STYLE,      ctx.outlineMode ? STYLE_DOT : STYLE_DASH);
            ObjectSetInteger(0, nm, OBJPROP_WIDTH,      1);
            ObjectSetInteger(0, nm, OBJPROP_FILL,       !ctx.outlineMode);
            ObjectSetInteger(0, nm, OBJPROP_BGCOLOR,    fillCol);
            ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
            ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);

            ObjectCreate(0, lnm, OBJ_TEXT, 0, lt, oteHi);
            ObjectSetString(0,  lnm, OBJPROP_TEXT,      "OTE");
            ObjectSetInteger(0, lnm, OBJPROP_COLOR,     brdCol);
            ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE,  7);
            ObjectSetString(0,  lnm, OBJPROP_FONT,      "Consolas");
            ObjectSetInteger(0, lnm, OBJPROP_ANCHOR,    ANCHOR_LOWER);
            ObjectSetInteger(0, lnm, OBJPROP_BACK,      true);
            ObjectSetInteger(0, lnm, OBJPROP_SELECTABLE,false);
         }
      }
   }
}

//+------------------------------------------------------------------+
// SetupEngine_ActiveSetupString — dashboard row
//+------------------------------------------------------------------+
string SetupEngine_ActiveSetupString(const SPAMContext &ctx)
{
   bool anyEnabled = ctx.showJudas || ctx.showSilverBullet ||
                     ctx.showCISD  || ctx.showOTE;
   if(!anyEnabled)          return "  Setup      all hidden";
   if(ctx.activeSetup == "") return "  Setup      no pattern active";
   return "  Setup      " + ctx.activeSetup;
}

#endif // PAM_SETUP_MQH
