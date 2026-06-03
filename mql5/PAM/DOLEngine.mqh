//+------------------------------------------------------------------+
//| PAM/DOLEngine.mqh  —  Draw on Liquidity Detection               |
//|                                                                  |
//| SMC / ICT Core Concept:                                         |
//|   Price is never random — it is always being "drawn" toward     |
//|   the nearest pool of resting orders. Identifying WHERE price   |
//|   is being drawn removes the guesswork from directional bias.   |
//|                                                                  |
//|   DOL UP   — nearest unswept buy-side liquidity pool above      |
//|              current price. Stops resting above equal highs or   |
//|              prior swing highs are the institutional target when  |
//|              the draw is bullish.                                 |
//|                                                                  |
//|   DOL DOWN — nearest unswept sell-side liquidity pool below      |
//|              current price. Stops below equal lows / prior swing  |
//|              lows are the institutional magnet for bearish draws. |
//|                                                                  |
//|   The DOL + trend alignment is the strongest confluence:         |
//|   Bullish trend + DOL UP  = continuation draw confirmed.         |
//|   Bearish trend + DOL DOWN = continuation draw confirmed.         |
//|   Trend vs DOL mismatch   = be cautious — manipulation possible. |
//+------------------------------------------------------------------+
#ifndef PAM_DOL_MQH
#define PAM_DOL_MQH
#include "Context.mqh"

//+------------------------------------------------------------------+
// DOLEngine_Compute
//   Scans ctx.liq[] for the nearest unswept levels above/below price.
//   Populates ctx.dolUp and ctx.dolDown.
//+------------------------------------------------------------------+
void DOLEngine_Compute(SPAMContext &ctx, double curPrice)
{
   ctx.dolUp   = 0;
   ctx.dolDown = 0;

   if(!ctx.showDOL) return;

   double nearestUp   =  DBL_MAX;
   double nearestDown = -DBL_MAX;

   for(int i = 0; i < ctx.nLiq; i++)
   {
      if(ctx.liq[i].swept) continue;

      double lp = ctx.liq[i].price;

      if(ctx.liq[i].type == LIQ_BUY_SIDE && lp > curPrice)
      {
         if(lp < nearestUp) { nearestUp = lp; ctx.dolUp = lp; }
      }
      else if(ctx.liq[i].type == LIQ_SELL_SIDE && lp < curPrice)
      {
         if(lp > nearestDown) { nearestDown = lp; ctx.dolDown = lp; }
      }
   }
}

//+------------------------------------------------------------------+
// DOLEngine_Draw
//   Dotted lines at DOL levels with directional arrow labels.
//   Drawn shorter than liquidity lines so they read as "targets"
//   rather than historical levels.
//+------------------------------------------------------------------+
void DOLEngine_Draw(const SPAMContext &ctx,
                    const datetime    &time[],
                    int                total,
                    const string      &pfx)
{
   if(!ctx.showDOL) return;
   if(ctx.dolUp <= 0 && ctx.dolDown <= 0) return;

   // Span: last quarter of lookback so the line is visually compact
   int      leftBar   = MathMin(ctx.lookback / 5, total - 1);
   datetime leftTime  = time[leftBar];
   datetime rightTime = time[0];

   if(ctx.dolUp > 0)
   {
      string nm  = pfx + "DOLUP";
      string lbl = pfx + "DOLUP_L";

      ObjectCreate(0, nm, OBJ_TREND, 0, leftTime, ctx.dolUp, rightTime, ctx.dolUp);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      C'230,190,0');
      ObjectSetInteger(0, nm, OBJPROP_STYLE,      STYLE_DOT);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,      2);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT,  true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK,       false);

      ObjectCreate(0, lbl, OBJ_TEXT, 0, leftTime, ctx.dolUp);
      ObjectSetString(0,  lbl, OBJPROP_TEXT,      "DOL ↑ BSL");
      ObjectSetInteger(0, lbl, OBJPROP_COLOR,     C'230,190,0');
      ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE,  7);
      ObjectSetString(0,  lbl, OBJPROP_FONT,      "Consolas");
      ObjectSetInteger(0, lbl, OBJPROP_ANCHOR,    ANCHOR_LOWER);
      ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, lbl, OBJPROP_BACK,      false);
   }

   if(ctx.dolDown > 0)
   {
      string nm  = pfx + "DOLDOWN";
      string lbl = pfx + "DOLDOWN_L";

      ObjectCreate(0, nm, OBJ_TREND, 0, leftTime, ctx.dolDown, rightTime, ctx.dolDown);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      C'230,120,0');
      ObjectSetInteger(0, nm, OBJPROP_STYLE,      STYLE_DOT);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,      2);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT,  true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK,       false);

      ObjectCreate(0, lbl, OBJ_TEXT, 0, leftTime, ctx.dolDown);
      ObjectSetString(0,  lbl, OBJPROP_TEXT,      "DOL ↓ SSL");
      ObjectSetInteger(0, lbl, OBJPROP_COLOR,     C'230,120,0');
      ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE,  7);
      ObjectSetString(0,  lbl, OBJPROP_FONT,      "Consolas");
      ObjectSetInteger(0, lbl, OBJPROP_ANCHOR,    ANCHOR_UPPER);
      ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, lbl, OBJPROP_BACK,      false);
   }
}

//+------------------------------------------------------------------+
// DOLEngine_DashString
//   Dashboard row showing the up/down draw targets with context.
//+------------------------------------------------------------------+
string DOLEngine_DashString(const SPAMContext &ctx, double curPrice)
{
   if(!ctx.showDOL) return "  DOL        hidden";
   if(ctx.dolUp <= 0 && ctx.dolDown <= 0) return "  DOL        no targets found";

   string res = "  DOL  ";

   if(ctx.dolUp > 0)
   {
      bool aligned = (ctx.trend == TREND_BULLISH);
      res += StringFormat(" ↑%.5f%s", ctx.dolUp, aligned ? " ✓" : "");
   }
   if(ctx.dolDown > 0)
   {
      bool aligned = (ctx.trend == TREND_BEARISH);
      res += StringFormat("  ↓%.5f%s", ctx.dolDown, aligned ? " ✓" : "");
   }
   return res;
}

#endif // PAM_DOL_MQH
