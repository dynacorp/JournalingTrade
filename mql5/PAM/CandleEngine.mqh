//+------------------------------------------------------------------+
//| PAM/CandleEngine.mqh  —  Candle psychology & classification     |
//|                                                                  |
//| For each recent bar:                                             |
//|  - Measures body size, wick size, total range vs ATR            |
//|  - Classifies into a personality type (ECandleType)             |
//|  - Generates an educational label                               |
//|  - Detects displacement, exhaustion, and compression events     |
//|                                                                  |
//| Labels shown ONLY on significant candles to avoid clutter.      |
//+------------------------------------------------------------------+
#ifndef PAM_CANDLE_MQH
#define PAM_CANDLE_MQH
#include "Context.mqh"

//+------------------------------------------------------------------+
// ClassifyCandle
//   Pure function: given one bar's OHLC + ATR value, returns
//   a fully populated SCandle struct.
//+------------------------------------------------------------------+
SCandle CandleEngine_ClassifyOne(int bar, datetime t,
                                  double o, double h, double l, double cls,
                                  double atr, double disp, EMode mode)
{
   SCandle sc;
   sc.bar       = bar;
   sc.time      = t;
   sc.showLabel = false;
   sc.col       = clrSilver;
   sc.label     = "";

   double totalRange = h - l;
   if(totalRange < 1e-10)
   {
      sc.type = CANDLE_INDECISION;
      sc.bodyRatio      = 0;
      sc.upperWickRatio = 0;
      sc.lowerWickRatio = 0;
      sc.rangeVsAtr     = 0;
      return sc;
   }

   double bodyTop    = MathMax(o, cls);
   double bodyBot    = MathMin(o, cls);
   double bodySize   = bodyTop - bodyBot;
   double upperWick  = h - bodyTop;
   double lowerWick  = bodyBot - l;
   bool   isBull     = (cls >= o);

   sc.bodyRatio      = bodySize   / totalRange;
   sc.upperWickRatio = upperWick  / totalRange;
   sc.lowerWickRatio = lowerWick  / totalRange;
   sc.rangeVsAtr     = (atr > 1e-10) ? totalRange / atr : 0;

   // --- Classify ---

   // Compression: range < 40% of ATR
   if(sc.rangeVsAtr < 0.40)
   {
      sc.type = CANDLE_COMPRESSION;
      // Only label during notable streaks — handled in Compute
      return sc;
   }

   // Displacement: large body + strong conviction
   double bodyVsAtr = (atr > 1e-10) ? bodySize / atr : 0;
   if(bodyVsAtr >= disp && sc.bodyRatio >= 0.60)
   {
      sc.type      = isBull ? CANDLE_DISPLACEMENT_BULL : CANDLE_DISPLACEMENT_BEAR;
      sc.col       = isBull ? C'0,200,120' : C'220,60,60';
      sc.showLabel = true;

      switch(mode)
      {
         case MODE_BEGINNER:
            sc.label = isBull ? "Strong Bull" : "Strong Bear";
            break;
         case MODE_ADVANCED:
            sc.label = isBull ? "Displacement ▲" : "Displacement ▼";
            break;
         case MODE_INSTITUTIONAL:
            sc.label = isBull ? "Inst. displacement ▲" : "Inst. displacement ▼";
            break;
      }
      return sc;
   }

   // Exhaustion bull: upper wick > 45% of range, small body at bottom
   if(sc.upperWickRatio >= 0.45 && sc.bodyRatio <= 0.30 && sc.rangeVsAtr >= 0.70)
   {
      sc.type      = CANDLE_EXHAUSTION_BULL;
      sc.col       = C'220,160,0';
      sc.showLabel = true;
      switch(mode)
      {
         case MODE_BEGINNER:
            sc.label = "Buyers rejected";
            break;
         case MODE_ADVANCED:
            sc.label = "Bull exhaustion";
            break;
         case MODE_INSTITUTIONAL:
            sc.label = "Supply absorption / stop hunt ↑";
            break;
      }
      return sc;
   }

   // Exhaustion bear: lower wick > 45% of range, small body at top
   if(sc.lowerWickRatio >= 0.45 && sc.bodyRatio <= 0.30 && sc.rangeVsAtr >= 0.70)
   {
      sc.type      = CANDLE_EXHAUSTION_BEAR;
      sc.col       = C'100,220,255';
      sc.showLabel = true;
      switch(mode)
      {
         case MODE_BEGINNER:
            sc.label = "Sellers rejected";
            break;
         case MODE_ADVANCED:
            sc.label = "Bear exhaustion";
            break;
         case MODE_INSTITUTIONAL:
            sc.label = "Demand absorption / stop hunt ↓";
            break;
      }
      return sc;
   }

   // Hammer: lower wick > 60%, small body in top third
   if(sc.lowerWickRatio >= 0.60 && bodyBot >= l + totalRange * 0.55)
   {
      sc.type      = CANDLE_HAMMER;
      sc.col       = C'0,200,120';
      sc.showLabel = true;
      switch(mode)
      {
         case MODE_BEGINNER:  sc.label = "Hammer (reversal signal)"; break;
         case MODE_ADVANCED:  sc.label = "Hammer / Pin Bar ↑"; break;
         case MODE_INSTITUTIONAL: sc.label = "Demand spike / OB wick"; break;
      }
      return sc;
   }

   // Shooting star: upper wick > 60%, small body in bottom third
   if(sc.upperWickRatio >= 0.60 && bodyTop <= l + totalRange * 0.45)
   {
      sc.type      = CANDLE_SHOOTING_STAR;
      sc.col       = C'220,60,60';
      sc.showLabel = true;
      switch(mode)
      {
         case MODE_BEGINNER:  sc.label = "Shooting Star (reversal signal)"; break;
         case MODE_ADVANCED:  sc.label = "Shooting Star / Pin Bar ↓"; break;
         case MODE_INSTITUTIONAL: sc.label = "Supply spike / OB wick"; break;
      }
      return sc;
   }

   // Indecision / doji: very small body
   if(sc.bodyRatio <= 0.15)
   {
      sc.type      = CANDLE_INDECISION;
      sc.col       = clrSilver;
      sc.showLabel = (sc.rangeVsAtr >= 0.60);   // only label large dojis
      switch(mode)
      {
         case MODE_BEGINNER:  sc.label = "Indecision"; break;
         case MODE_ADVANCED:  sc.label = "Doji / equilibrium"; break;
         case MODE_INSTITUTIONAL: sc.label = "Order flow balanced"; break;
      }
      return sc;
   }

   // Strong bull / bear conviction candle
   if(sc.bodyRatio >= 0.55)
   {
      sc.type      = isBull ? CANDLE_BULL_STRONG : CANDLE_BEAR_STRONG;
      sc.col       = isBull ? C'0,180,100' : C'200,50,50';
      // Label only if notably large
      sc.showLabel = (sc.rangeVsAtr >= 1.0);
      switch(mode)
      {
         case MODE_BEGINNER:  sc.label = isBull ? "Strong Bull" : "Strong Bear"; break;
         case MODE_ADVANCED:  sc.label = isBull ? "Conviction bull" : "Conviction bear"; break;
         case MODE_INSTITUTIONAL: sc.label = isBull ? "OF positive" : "OF negative"; break;
      }
      return sc;
   }

   sc.type = CANDLE_NEUTRAL;
   return sc;
}

//+------------------------------------------------------------------+
// CandleEngine_Compute
//   Classifies the most recent PAM_MAX_CANDLES bars.
//   Sets ctx.dispBullRecent, ctx.dispBearRecent, etc.
//+------------------------------------------------------------------+
void CandleEngine_Compute(SPAMContext    &ctx,
                           const double   &open[],
                           const double   &high[],
                           const double   &low[],
                           const double   &close[],
                           const datetime &time[],
                           const double   &atr[],
                           int             total)
{
   ctx.nCandles         = 0;
   ctx.dispBullRecent   = false;
   ctx.dispBearRecent   = false;
   ctx.exhaustBullRecent = false;
   ctx.exhaustBearRecent = false;

   int bars = MathMin(PAM_MAX_CANDLES, total - 1);
   for(int i = 0; i < bars; i++)
   {
      SCandle sc = CandleEngine_ClassifyOne(i, time[i],
                                            open[i], high[i], low[i], close[i],
                                            atr[i], ctx.dispThresh, ctx.mode);
      ctx.candles[ctx.nCandles] = sc;
      ctx.nCandles++;

      // Set recent flags (within last 5 bars)
      if(i < 5)
      {
         if(sc.type == CANDLE_DISPLACEMENT_BULL) ctx.dispBullRecent   = true;
         if(sc.type == CANDLE_DISPLACEMENT_BEAR) ctx.dispBearRecent   = true;
         if(sc.type == CANDLE_EXHAUSTION_BULL)   ctx.exhaustBullRecent = true;
         if(sc.type == CANDLE_EXHAUSTION_BEAR)   ctx.exhaustBearRecent = true;
      }
   }
}

//+------------------------------------------------------------------+
// CandleEngine_Draw
//   Places labels on significant candles.
//+------------------------------------------------------------------+
void CandleEngine_Draw(const SPAMContext &ctx,
                        const double      &high[],
                        const double      &low[],
                        const string      &pfx)
{
   if(!ctx.showCandles) return;

   for(int i = 0; i < ctx.nCandles; i++)
   {
      SCandle sc = ctx.candles[i];
      if(!sc.showLabel || sc.label == "") continue;

      bool aboveCandle = (sc.type == CANDLE_EXHAUSTION_BULL ||
                          sc.type == CANDLE_SHOOTING_STAR  ||
                          sc.type == CANDLE_BEAR_STRONG    ||
                          sc.type == CANDLE_DISPLACEMENT_BEAR);

      double py = aboveCandle ? high[sc.bar] + ctx.atr * 0.25
                              : low[sc.bar]  - ctx.atr * 0.25;

      string nm = pfx + "CL" + IntegerToString(i);
      ObjectCreate(0, nm, OBJ_TEXT, 0, sc.time, py);
      ObjectSetString(0,  nm, OBJPROP_TEXT,       sc.label);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      sc.col);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,   7);
      ObjectSetString(0,  nm, OBJPROP_FONT,       "Consolas");
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR,     aboveCandle ? ANCHOR_LOWER : ANCHOR_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   }
}

//+------------------------------------------------------------------+
// Utility: get candle type string for dashboard / replay
//+------------------------------------------------------------------+
string CandleEngine_TypeString(ECandleType t)
{
   switch(t)
   {
      case CANDLE_BULL_STRONG:        return "Strong Bull";
      case CANDLE_BEAR_STRONG:        return "Strong Bear";
      case CANDLE_DISPLACEMENT_BULL:  return "Displacement Bull";
      case CANDLE_DISPLACEMENT_BEAR:  return "Displacement Bear";
      case CANDLE_EXHAUSTION_BULL:    return "Bull Exhaustion";
      case CANDLE_EXHAUSTION_BEAR:    return "Bear Exhaustion";
      case CANDLE_INDECISION:         return "Indecision/Doji";
      case CANDLE_HAMMER:             return "Hammer";
      case CANDLE_SHOOTING_STAR:      return "Shooting Star";
      case CANDLE_COMPRESSION:        return "Compression";
      default:                        return "Neutral";
   }
}

#endif // PAM_CANDLE_MQH
