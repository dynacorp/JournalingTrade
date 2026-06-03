//+------------------------------------------------------------------+
//| PAM/PremDiscEngine.mqh  —  Premium / Discount / Equilibrium     |
//|                                                                  |
//| SMC Core Concept:                                                |
//|   Every market move has a "range" defined by the last confirmed  |
//|   swing high and swing low. That range is divided into:          |
//|                                                                  |
//|   PREMIUM  (above 50%)  — price is expensive relative to range  |
//|             Bearish bias: sell here if trend is down.            |
//|             Bullish caution: buying here is higher risk.         |
//|                                                                  |
//|   EQUILIBRIUM (50%)     — balanced, fair value                   |
//|             No directional edge from position alone.             |
//|             Structure and momentum become the primary filter.    |
//|                                                                  |
//|   DISCOUNT  (below 50%) — price is cheap relative to range      |
//|             Bullish bias: buy here if trend is up.               |
//|             Bearish caution: selling here is higher risk.        |
//|                                                                  |
//| Optional Fibonacci levels: 0.236, 0.382, 0.618, 0.786           |
//| These mark "optimal trade entry" zones used institutionally.     |
//+------------------------------------------------------------------+
#ifndef PAM_PREMDISC_MQH
#define PAM_PREMDISC_MQH
#include "Context.mqh"

//+------------------------------------------------------------------+
// PremDiscEngine_Compute
//   Calculates the equilibrium and price position using the last
//   confirmed swing high / swing low from the structure engine.
//+------------------------------------------------------------------+
void PremDiscEngine_Compute(SPAMContext &ctx, double curPrice)
{
   ctx.equilPrice  = 0;
   ctx.premDiscPct = 50;

   if(ctx.lastSwH <= 0 || ctx.lastSwL <= 0) return;
   if(ctx.lastSwH <= ctx.lastSwL) return;

   double range    = ctx.lastSwH - ctx.lastSwL;
   ctx.equilPrice  = ctx.lastSwL + range * 0.50;
   ctx.premDiscPct = (range > 1e-10) ?
                     (curPrice - ctx.lastSwL) / range * 100.0 : 50.0;
   ctx.premDiscPct = MathMax(-10, MathMin(110, ctx.premDiscPct));
}

//+------------------------------------------------------------------+
// PremDiscEngine_Draw
//   Visual layers (back to front):
//   1. Faint background fill for premium / discount zones
//   2. Fibonacci internal levels (0.236, 0.382, 0.618, 0.786)
//   3. Equilibrium line (50%)
//   4. Swing boundary lines (0% = lastSwL, 100% = lastSwH)
//+------------------------------------------------------------------+
void PremDiscEngine_Draw(const SPAMContext &ctx,
                          const datetime   &time[],
                          int               total,
                          const string     &pfx,
                          bool              showFibs)
{
   if(!ctx.showPremDisc) return;
   if(ctx.lastSwH <= 0 || ctx.lastSwL <= 0) return;
   if(ctx.lastSwH <= ctx.lastSwL) return;

   int      leftBar   = MathMin(ctx.lookback, total - 1);
   datetime leftTime  = time[leftBar];
   datetime rightTime = time[0];
   double   hi        = ctx.lastSwH;
   double   lo        = ctx.lastSwL;
   double   mid       = ctx.equilPrice;
   double   range     = hi - lo;

   // --- Premium zone (above 50%) ---
   string pmNm = pfx + "PREM";
   ObjectCreate(0, pmNm, OBJ_RECTANGLE, 0, leftTime, hi, rightTime, mid);
   ObjectSetInteger(0, pmNm, OBJPROP_COLOR,      C'120,20,20');
   ObjectSetInteger(0, pmNm, OBJPROP_STYLE,      ctx.outlineMode ? STYLE_DOT : STYLE_SOLID);
   ObjectSetInteger(0, pmNm, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, pmNm, OBJPROP_FILL,       !ctx.outlineMode);
   ObjectSetInteger(0, pmNm, OBJPROP_BGCOLOR,    C'18,5,5');
   ObjectSetInteger(0, pmNm, OBJPROP_BACK,       true);
   ObjectSetInteger(0, pmNm, OBJPROP_SELECTABLE, false);

   // --- Discount zone (below 50%) ---
   string dcNm = pfx + "DISC";
   ObjectCreate(0, dcNm, OBJ_RECTANGLE, 0, leftTime, mid, rightTime, lo);
   ObjectSetInteger(0, dcNm, OBJPROP_COLOR,      C'20,120,20');
   ObjectSetInteger(0, dcNm, OBJPROP_STYLE,      ctx.outlineMode ? STYLE_DOT : STYLE_SOLID);
   ObjectSetInteger(0, dcNm, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, dcNm, OBJPROP_FILL,       !ctx.outlineMode);
   ObjectSetInteger(0, dcNm, OBJPROP_BGCOLOR,    C'5,18,5');
   ObjectSetInteger(0, dcNm, OBJPROP_BACK,       true);
   ObjectSetInteger(0, dcNm, OBJPROP_SELECTABLE, false);

   // --- Swing boundary dashed lines ---
   // Top (100% — swing high)
   string hiNm = pfx + "PDHIGH";
   ObjectCreate(0, hiNm, OBJ_TREND, 0, leftTime, hi, rightTime, hi);
   ObjectSetInteger(0, hiNm, OBJPROP_COLOR,      C'180,50,50');
   ObjectSetInteger(0, hiNm, OBJPROP_STYLE,      STYLE_DASH);
   ObjectSetInteger(0, hiNm, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, hiNm, OBJPROP_RAY_RIGHT,  true);
   ObjectSetInteger(0, hiNm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, hiNm, OBJPROP_BACK,       true);

   string hiLbl = pfx + "PDHIGHL";
   ObjectCreate(0, hiLbl, OBJ_TEXT, 0, leftTime, hi);
   ObjectSetString(0,  hiLbl, OBJPROP_TEXT,      "100%  SwH");
   ObjectSetInteger(0, hiLbl, OBJPROP_COLOR,     C'180,80,80');
   ObjectSetInteger(0, hiLbl, OBJPROP_FONTSIZE,  7);
   ObjectSetString(0,  hiLbl, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, hiLbl, OBJPROP_ANCHOR,    ANCHOR_LOWER);
   ObjectSetInteger(0, hiLbl, OBJPROP_SELECTABLE,false);

   // Bottom (0% — swing low)
   string loNm = pfx + "PDLOW";
   ObjectCreate(0, loNm, OBJ_TREND, 0, leftTime, lo, rightTime, lo);
   ObjectSetInteger(0, loNm, OBJPROP_COLOR,      C'50,180,50');
   ObjectSetInteger(0, loNm, OBJPROP_STYLE,      STYLE_DASH);
   ObjectSetInteger(0, loNm, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, loNm, OBJPROP_RAY_RIGHT,  true);
   ObjectSetInteger(0, loNm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, loNm, OBJPROP_BACK,       true);

   string loLbl = pfx + "PDLOWL";
   ObjectCreate(0, loLbl, OBJ_TEXT, 0, leftTime, lo);
   ObjectSetString(0,  loLbl, OBJPROP_TEXT,      "0%    SwL");
   ObjectSetInteger(0, loLbl, OBJPROP_COLOR,     C'80,180,80');
   ObjectSetInteger(0, loLbl, OBJPROP_FONTSIZE,  7);
   ObjectSetString(0,  loLbl, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, loLbl, OBJPROP_ANCHOR,    ANCHOR_UPPER);
   ObjectSetInteger(0, loLbl, OBJPROP_SELECTABLE,false);

   // --- Equilibrium line (50%) ---
   string eqNm = pfx + "EQ";
   ObjectCreate(0, eqNm, OBJ_TREND, 0, leftTime, mid, rightTime, mid);
   ObjectSetInteger(0, eqNm, OBJPROP_COLOR,      C'200,200,200');
   ObjectSetInteger(0, eqNm, OBJPROP_STYLE,      STYLE_DASH);
   ObjectSetInteger(0, eqNm, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, eqNm, OBJPROP_RAY_RIGHT,  true);
   ObjectSetInteger(0, eqNm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, eqNm, OBJPROP_BACK,       true);

   string eqLbl = pfx + "EQL";
   ObjectCreate(0, eqLbl, OBJ_TEXT, 0, leftTime, mid);
   ObjectSetString(0,  eqLbl, OBJPROP_TEXT,      "EQ 50%");
   ObjectSetInteger(0, eqLbl, OBJPROP_COLOR,     C'180,180,180');
   ObjectSetInteger(0, eqLbl, OBJPROP_FONTSIZE,  7);
   ObjectSetString(0,  eqLbl, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, eqLbl, OBJPROP_ANCHOR,    ANCHOR_LOWER);
   ObjectSetInteger(0, eqLbl, OBJPROP_SELECTABLE,false);

   // --- Optional Fibonacci OTE levels ---
   if(showFibs)
   {
      double fibs[4] = { 0.236, 0.382, 0.618, 0.786 };
      string fibLabels[4] = { "23.6%", "38.2%", "61.8%  OTE", "78.6%  OTE" };
      color  fibCols[4]   = { C'80,80,100', C'80,80,120', C'120,80,120', C'140,80,120' };

      for(int f = 0; f < 4; f++)
      {
         double fp   = lo + range * fibs[f];
         string fnm  = pfx + "FIB" + IntegerToString(f);
         string flbl = pfx + "FIBL" + IntegerToString(f);

         ObjectCreate(0, fnm, OBJ_TREND, 0, leftTime, fp, rightTime, fp);
         ObjectSetInteger(0, fnm, OBJPROP_COLOR,      fibCols[f]);
         ObjectSetInteger(0, fnm, OBJPROP_STYLE,      STYLE_DOT);
         ObjectSetInteger(0, fnm, OBJPROP_WIDTH,      1);
         ObjectSetInteger(0, fnm, OBJPROP_RAY_RIGHT,  true);
         ObjectSetInteger(0, fnm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, fnm, OBJPROP_BACK,       true);

         ObjectCreate(0, flbl, OBJ_TEXT, 0, leftTime, fp);
         ObjectSetString(0,  flbl, OBJPROP_TEXT,      fibLabels[f]);
         ObjectSetInteger(0, flbl, OBJPROP_COLOR,     fibCols[f]);
         ObjectSetInteger(0, flbl, OBJPROP_FONTSIZE,  6);
         ObjectSetString(0,  flbl, OBJPROP_FONT,      "Consolas");
         ObjectSetInteger(0, flbl, OBJPROP_ANCHOR,    ANCHOR_UPPER);
         ObjectSetInteger(0, flbl, OBJPROP_SELECTABLE,false);
      }
   }
}

//+------------------------------------------------------------------+
// Utility: educational position string for dashboard
//+------------------------------------------------------------------+
string PremDiscEngine_PositionString(const SPAMContext &ctx, EMode mode)
{
   if(ctx.equilPrice == 0) return "  PD Grid    no swing data";

   string zone;
   if(ctx.premDiscPct >= 70)      zone = "PREMIUM (>70%)  — expensive";
   else if(ctx.premDiscPct >= 50) zone = "PREMIUM NEUTRAL — above EQ";
   else if(ctx.premDiscPct >= 30) zone = "DISCOUNT NEUTRAL — below EQ";
   else                           zone = "DISCOUNT (<30%) — cheap";

   string advNote = "";
   switch(mode)
   {
      case MODE_BEGINNER:
         if(ctx.premDiscPct >= 60)
            advNote = " | Risky to buy here";
         else if(ctx.premDiscPct <= 40)
            advNote = " | Better value for longs";
         break;
      case MODE_ADVANCED:
         if(ctx.trend == TREND_BULLISH && ctx.premDiscPct <= 40)
            advNote = " ✓ Bullish confluence";
         else if(ctx.trend == TREND_BEARISH && ctx.premDiscPct >= 60)
            advNote = " ✓ Bearish confluence";
         else if(ctx.trend != TREND_RANGING)
            advNote = " ✗ Counter-PD position";
         break;
      case MODE_INSTITUTIONAL:
         if(ctx.trend == TREND_BULLISH && ctx.premDiscPct <= 38.2)
            advNote = " ✓ OTE zone — high-prob long";
         else if(ctx.trend == TREND_BEARISH && ctx.premDiscPct >= 61.8)
            advNote = " ✓ OTE zone — high-prob short";
         else if(ctx.trend != TREND_RANGING)
            advNote = " — wait for OTE retracement";
         break;
   }

   return StringFormat("  PD Grid    %.0f%%  %s%s", ctx.premDiscPct, zone, advNote);
}

//+------------------------------------------------------------------+
// PremDiscEngine bonus for ScoringEngine (called from ScoringEngine)
//+------------------------------------------------------------------+
double PremDiscEngine_StructureBonus(const SPAMContext &ctx)
{
   if(ctx.equilPrice == 0) return 0;

   // Reward alignment: bullish trend + price in discount, or bearish + premium
   if(ctx.trend == TREND_BULLISH && ctx.premDiscPct <= 40) return 15;
   if(ctx.trend == TREND_BEARISH && ctx.premDiscPct >= 60) return 15;

   // Penalise counter-position only mildly (position alone isn't wrong)
   if(ctx.trend == TREND_BULLISH && ctx.premDiscPct >= 70) return -10;
   if(ctx.trend == TREND_BEARISH && ctx.premDiscPct <= 30) return -10;

   return 0;
}

#endif // PAM_PREMDISC_MQH
