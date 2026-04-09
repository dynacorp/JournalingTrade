//+------------------------------------------------------------------+
//|                                                 WickAnalysis.mq5  |
//|                        TradeMind Wick Classification Indicator     |
//|  Classifies each candle wick as: Rejection, Liquidity Taken,      |
//|  Failed Continuation, Stop Hunt, Imbalance, Sweep, Exhaustion.    |
//|  Also classifies candles as: Momentum, Doji.                      |
//+------------------------------------------------------------------+
#property copyright "TradeMind"
#property link      ""
#property version   "2.00"
#property strict
#property indicator_chart_window
#property indicator_plots 0

//+------------------------------------------------------------------+
//| Enums & Constants                                                  |
//+------------------------------------------------------------------+
enum ENUM_WICK_TYPE
{
   WICK_REJECTION         = 0x01, // R — price rejected
   WICK_LIQUIDITY         = 0x02, // L — liquidity taken (swept swing)
   WICK_FAILED_CONT       = 0x04, // F — failed continuation
   WICK_STOP_HUNT         = 0x08, // S — stop hunt (swept equal levels)
   WICK_IMBALANCE         = 0x10, // I — created FVG imbalance
   WICK_SWEEP             = 0x20, // SWP — liquidity sweep
   WICK_EXHAUSTION        = 0x40, // EXH — exhaustion wick
};

//--- Candle-level flags (separate namespace from wick flags)
#define CANDLE_MOMENTUM   0x01   // MOM — strong displacement candle
#define CANDLE_DOJI       0x02   // DOJ — indecision/doji candle

//+------------------------------------------------------------------+
//| Input Parameters                                                   |
//+------------------------------------------------------------------+
input group "=== Detection ==="
input int      InpMaxBars            = 200;      // Max bars to analyze
input int      InpSwingStrength      = 5;        // Swing lookback (bars each side)
input double   InpMinWickATR         = 0.3;      // Min wick size to classify (x ATR)
input int      InpATRPeriod          = 14;       // ATR period
input int      InpMAPeriod           = 20;       // MA period (trend detection)

input group "=== Rejection ==="
input double   InpRejectionRatio     = 0.5;      // Wick/range ratio for rejection
input double   InpRejectionBodyRatio = 2.0;      // Wick/body ratio for rejection

input group "=== Liquidity ==="
input int      InpLiqLookback        = 20;       // Lookback for swing highs/lows

input group "=== Stop Hunt ==="
input double   InpEqualTolerance     = 0.3;      // Equal level tolerance (x ATR)
input int      InpMinEqualTouches    = 2;        // Min touches for equal level
input int      InpEqualLookback      = 30;       // Lookback for equal levels

input group "=== Sweep ==="
input int      InpSweepLookback      = 20;       // Lookback bars for sweep detection

input group "=== Momentum ==="
input double   InpMomBodyRatio       = 0.7;      // Min body/range ratio for momentum
input double   InpMomMinATR          = 0.8;      // Min candle range (x ATR) for momentum

input group "=== Exhaustion ==="
input double   InpExhWickRatio       = 0.5;      // Min wick/range for exhaustion
input int      InpExhLookback        = 10;       // Bars to check for prior move
input double   InpExhMoveATR         = 2.0;      // Min prior move size (x ATR)

input group "=== Doji ==="
input double   InpDojiBodyRatio      = 0.1;      // Max body/range ratio for doji
input double   InpDojiMinATR         = 0.3;      // Min candle range (x ATR) for doji

input group "=== Visual ==="
input int      InpFontSize           = 7;        // Font size
input bool     InpShowUpperLabels    = true;     // Show upper wick labels
input bool     InpShowLowerLabels    = true;     // Show lower wick labels
input bool     InpShowCandleLabels   = true;     // Show candle labels (MOM/DOJ)
input int      InpMaxLabels          = 100;      // Max labels to draw

input group "=== Colors ==="
input color    InpRejectionColor     = clrRed;         // Rejection (R)
input color    InpLiquidityColor     = clrMagenta;     // Liquidity (L)
input color    InpFailedContColor    = clrOrange;      // Failed Continuation (F)
input color    InpStopHuntColor      = clrGold;        // Stop Hunt (S)
input color    InpImbalanceColor     = clrDodgerBlue;  // Imbalance (I)
input color    InpSweepColor         = clrDeepPink;    // Sweep (SWP)
input color    InpExhaustionColor    = clrCoral;       // Exhaustion (EXH)
input color    InpMomentumColor      = clrLime;        // Momentum (MOM)
input color    InpDojiColor          = clrSilver;      // Doji (DOJ)
input color    InpMultiColor         = clrWhite;       // Multiple types

//+------------------------------------------------------------------+
//| Structs                                                            |
//+------------------------------------------------------------------+
struct WickInfo
{
   int   upperFlags;    // Bitmask of ENUM_WICK_TYPE for upper wick
   int   lowerFlags;    // Bitmask of ENUM_WICK_TYPE for lower wick
   int   candleFlags;   // Bitmask of candle-level flags (MOM, DOJ)
};

struct SwingPoint
{
   int      bar;
   double   price;
   bool     isHigh;
};

//+------------------------------------------------------------------+
//| Globals                                                            |
//+------------------------------------------------------------------+
string   g_prefix = "WA_";
int      g_lastCalculatedBars = 0;
double   g_atrValue = 0;
double   g_ma[];

//+------------------------------------------------------------------+
//| OnInit                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   CleanAllObjects();
   Comment("");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanAllObjects();
   Comment("");
}

//+------------------------------------------------------------------+
//| OnCalculate                                                        |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < InpMAPeriod + InpSwingStrength + 2) return rates_total;

   //--- New bar guard
   if(rates_total == g_lastCalculatedBars) return rates_total;
   g_lastCalculatedBars = rates_total;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int limit = MathMin(rates_total - 1, InpMaxBars);

   //--- 1. Calculate ATR
   g_atrValue = CalculateATR(high, low, close, rates_total);
   if(g_atrValue == 0) return rates_total;

   //--- 2. Calculate MA for trend detection
   CalculateMA(close, rates_total, limit);

   //--- 3. Detect swing points
   SwingPoint swings[];
   int swingCount = 0;
   DetectSwingPoints(high, low, swings, swingCount, limit, rates_total);

   //--- 4. Classify each bar's wicks and candle type
   WickInfo wicks[];
   ArrayResize(wicks, limit + 1);

   for(int i = 1; i <= limit; i++)
   {
      wicks[i].upperFlags  = 0;
      wicks[i].lowerFlags  = 0;
      wicks[i].candleFlags = 0;

      double body_top    = MathMax(open[i], close[i]);
      double body_bottom = MathMin(open[i], close[i]);
      double upper_wick  = high[i] - body_top;
      double lower_wick  = body_bottom - low[i];
      double range       = high[i] - low[i];
      double body        = body_top - body_bottom;

      //--- Candle-level classifications (don't need significant wick)
      if(range > 0)
      {
         if(IsMomentumCandle(body, range))
            wicks[i].candleFlags |= CANDLE_MOMENTUM;
         if(IsDoji(body, range))
            wicks[i].candleFlags |= CANDLE_DOJI;
      }

      //--- Skip tiny wicks for wick-level classifications
      bool upperSig = (upper_wick > g_atrValue * InpMinWickATR);
      bool lowerSig = (lower_wick > g_atrValue * InpMinWickATR);

      if(!upperSig && !lowerSig) continue;

      //--- Check each wick classification
      if(upperSig)
      {
         if(IsRejection(upper_wick, range, body))
            wicks[i].upperFlags |= WICK_REJECTION;
         if(IsLiquidityTaken(true, high[i], close[i], swings, swingCount, i))
            wicks[i].upperFlags |= WICK_LIQUIDITY;
         if(IsFailedContinuation(true, upper_wick, range, i, close))
            wicks[i].upperFlags |= WICK_FAILED_CONT;
         if(IsStopHunt(true, high[i], close[i], high, low, i, limit))
            wicks[i].upperFlags |= WICK_STOP_HUNT;
         if(i >= 1 && i + 1 <= limit)
            if(IsImbalance(true, i, high, low))
               wicks[i].upperFlags |= WICK_IMBALANCE;
         if(IsSweepWick(true, high[i], close[i], high, low, i, limit))
            wicks[i].upperFlags |= WICK_SWEEP;
         if(IsExhaustionWick(true, upper_wick, range, i, close, limit))
            wicks[i].upperFlags |= WICK_EXHAUSTION;
      }

      if(lowerSig)
      {
         if(IsRejection(lower_wick, range, body))
            wicks[i].lowerFlags |= WICK_REJECTION;
         if(IsLiquidityTaken(false, low[i], close[i], swings, swingCount, i))
            wicks[i].lowerFlags |= WICK_LIQUIDITY;
         if(IsFailedContinuation(false, lower_wick, range, i, close))
            wicks[i].lowerFlags |= WICK_FAILED_CONT;
         if(IsStopHunt(false, low[i], close[i], high, low, i, limit))
            wicks[i].lowerFlags |= WICK_STOP_HUNT;
         if(i >= 1 && i + 1 <= limit)
            if(IsImbalance(false, i, high, low))
               wicks[i].lowerFlags |= WICK_IMBALANCE;
         if(IsSweepWick(false, low[i], close[i], high, low, i, limit))
            wicks[i].lowerFlags |= WICK_SWEEP;
         if(IsExhaustionWick(false, lower_wick, range, i, close, limit))
            wicks[i].lowerFlags |= WICK_EXHAUSTION;
      }
   }

   //--- 5. Draw labels
   CleanAllObjects();
   DrawWickLabels(wicks, time, open, close, high, low, limit);

   return rates_total;
}

//+------------------------------------------------------------------+
//| CalculateATR — simple ATR at bar 1                                 |
//+------------------------------------------------------------------+
double CalculateATR(const double &high[], const double &low[],
                    const double &close[], int totalBars)
{
   if(totalBars < InpATRPeriod + 2) return 0;
   double sum = 0;
   for(int i = 1; i <= InpATRPeriod; i++)
   {
      double tr1 = high[i] - low[i];
      double tr2 = MathAbs(high[i] - close[i + 1]);
      double tr3 = MathAbs(low[i] - close[i + 1]);
      sum += MathMax(tr1, MathMax(tr2, tr3));
   }
   return sum / InpATRPeriod;
}

//+------------------------------------------------------------------+
//| CalculateMA — simple SMA into g_ma[]                               |
//+------------------------------------------------------------------+
void CalculateMA(const double &close[], int totalBars, int limit)
{
   ArrayResize(g_ma, totalBars);
   ArrayInitialize(g_ma, 0);
   ArraySetAsSeries(g_ma, true);

   for(int i = limit - 1; i >= 0; i--)
   {
      if(i + InpMAPeriod >= totalBars) continue;
      double sum = 0;
      for(int j = 0; j < InpMAPeriod; j++)
         sum += close[i + j];
      g_ma[i] = sum / InpMAPeriod;
   }
}

//+------------------------------------------------------------------+
//| DetectSwingPoints — N-bar swing highs and lows                     |
//+------------------------------------------------------------------+
void DetectSwingPoints(const double &high[], const double &low[],
                       SwingPoint &swings[], int &count,
                       int limit, int totalBars)
{
   count = 0;
   int maxSwings = limit;
   ArrayResize(swings, maxSwings);

   for(int i = InpSwingStrength; i <= limit - InpSwingStrength; i++)
   {
      //--- Swing high
      bool isSwingHigh = true;
      for(int j = 1; j <= InpSwingStrength; j++)
      {
         if(high[i] <= high[i - j] || high[i] <= high[i + j])
         { isSwingHigh = false; break; }
      }
      if(isSwingHigh && count < maxSwings)
      {
         swings[count].bar    = i;
         swings[count].price  = high[i];
         swings[count].isHigh = true;
         count++;
      }

      //--- Swing low
      bool isSwingLow = true;
      for(int j = 1; j <= InpSwingStrength; j++)
      {
         if(low[i] >= low[i - j] || low[i] >= low[i + j])
         { isSwingLow = false; break; }
      }
      if(isSwingLow && count < maxSwings)
      {
         swings[count].bar    = i;
         swings[count].price  = low[i];
         swings[count].isHigh = false;
         count++;
      }
   }
   ArrayResize(swings, count);
}

//+------------------------------------------------------------------+
//| IsRejection — wick dominates candle range                          |
//+------------------------------------------------------------------+
bool IsRejection(double wickSize, double range, double body)
{
   if(range == 0) return false;
   if(wickSize / range >= InpRejectionRatio) return true;
   if(body > 0 && wickSize / body >= InpRejectionBodyRatio) return true;
   return false;
}

//+------------------------------------------------------------------+
//| IsLiquidityTaken — wick swept a swing point, close came back       |
//+------------------------------------------------------------------+
bool IsLiquidityTaken(bool isUpper, double wickExtreme, double closePrice,
                      const SwingPoint &swings[], int swingCount, int bar)
{
   for(int i = 0; i < swingCount; i++)
   {
      if(swings[i].bar <= bar) continue;
      if(swings[i].bar > bar + InpLiqLookback) continue;

      if(isUpper && swings[i].isHigh)
      {
         if(wickExtreme > swings[i].price && closePrice < swings[i].price)
            return true;
      }
      else if(!isUpper && !swings[i].isHigh)
      {
         if(wickExtreme < swings[i].price && closePrice > swings[i].price)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| IsFailedContinuation — wick in trend direction but close reverses  |
//+------------------------------------------------------------------+
bool IsFailedContinuation(bool isUpper, double wickSize,
                          double range, int bar, const double &close[])
{
   if(range == 0 || g_ma[bar] == 0) return false;
   if(wickSize / range < 0.3) return false;

   bool uptrend = close[bar] > g_ma[bar];

   if(isUpper && uptrend) return true;
   if(!isUpper && !uptrend) return true;

   return false;
}

//+------------------------------------------------------------------+
//| IsStopHunt — wick swept through equal highs/lows                   |
//+------------------------------------------------------------------+
bool IsStopHunt(bool isUpper, double wickExtreme, double closePrice,
                const double &high[], const double &low[],
                int bar, int limit)
{
   double tol = g_atrValue * InpEqualTolerance;
   int endBar = MathMin(bar + InpEqualLookback, limit);

   if(isUpper)
   {
      double targetLevel = 0;
      int touches = 0;

      for(int i = bar + 1; i <= endBar; i++)
      {
         double h = high[i];
         if(targetLevel == 0) { targetLevel = h; touches = 1; continue; }
         if(MathAbs(h - targetLevel) <= tol)
         {
            touches++;
            targetLevel = (targetLevel * (touches - 1) + h) / touches;
         }
      }

      if(touches >= InpMinEqualTouches)
      {
         if(wickExtreme > targetLevel + tol && closePrice < targetLevel)
            return true;
      }
   }
   else
   {
      double targetLevel = 0;
      int touches = 0;

      for(int i = bar + 1; i <= endBar; i++)
      {
         double l = low[i];
         if(targetLevel == 0) { targetLevel = l; touches = 1; continue; }
         if(MathAbs(l - targetLevel) <= tol)
         {
            touches++;
            targetLevel = (targetLevel * (touches - 1) + l) / touches;
         }
      }

      if(touches >= InpMinEqualTouches)
      {
         if(wickExtreme < targetLevel - tol && closePrice > targetLevel)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| IsImbalance — wick creates a Fair Value Gap                        |
//+------------------------------------------------------------------+
bool IsImbalance(bool isUpper, int bar,
                 const double &high[], const double &low[])
{
   int newer = bar - 1;
   int older = bar + 1;

   if(isUpper)
   {
      if(low[newer] > high[older])
         return true;
   }
   else
   {
      if(high[newer] < low[older])
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| IsSweepWick — wick swept beyond recent range extreme               |
//|  SWP↑ = upper wick swept above recent highs, close rejected back   |
//|  SWP↓ = lower wick swept below recent lows, close rejected back    |
//+------------------------------------------------------------------+
bool IsSweepWick(bool isUpper, double wickExtreme, double closePrice,
                 const double &high[], const double &low[],
                 int bar, int limit)
{
   int endBar = MathMin(bar + InpSweepLookback, limit);
   if(bar + 1 > limit) return false;

   if(isUpper)
   {
      //--- Find highest high in lookback window
      double recentHigh = high[bar + 1];
      for(int i = bar + 2; i <= endBar; i++)
         if(high[i] > recentHigh) recentHigh = high[i];

      //--- Wick pierced above recent high AND close came back below it
      if(wickExtreme > recentHigh && closePrice <= recentHigh)
         return true;
   }
   else
   {
      //--- Find lowest low in lookback window
      double recentLow = low[bar + 1];
      for(int i = bar + 2; i <= endBar; i++)
         if(low[i] < recentLow) recentLow = low[i];

      //--- Wick pierced below recent low AND close came back above it
      if(wickExtreme < recentLow && closePrice >= recentLow)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| IsExhaustionWick — long wick at the end of an extended move        |
//|  Upper wick after sustained up move = bullish exhaustion            |
//|  Lower wick after sustained down move = bearish exhaustion          |
//+------------------------------------------------------------------+
bool IsExhaustionWick(bool isUpper, double wickSize, double range,
                      int bar, const double &close[], int limit)
{
   if(range == 0) return false;
   //--- Wick must be significant portion of candle
   if(wickSize / range < InpExhWickRatio) return false;

   int endBar = MathMin(bar + InpExhLookback, limit);
   if(endBar <= bar + 1) return false;

   if(isUpper)
   {
      //--- Check for prior sustained upward move
      double move = close[bar + 1] - close[endBar];
      if(move > g_atrValue * InpExhMoveATR)
         return true;
   }
   else
   {
      //--- Check for prior sustained downward move
      double move = close[endBar] - close[bar + 1];
      if(move > g_atrValue * InpExhMoveATR)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| IsMomentumCandle — strong displacement, body dominates range       |
//+------------------------------------------------------------------+
bool IsMomentumCandle(double body, double range)
{
   if(range == 0) return false;
   //--- Range must be meaningful (not a tiny candle)
   if(range < g_atrValue * InpMomMinATR) return false;
   //--- Body takes up most of the range = strong commitment
   return (body / range >= InpMomBodyRatio);
}

//+------------------------------------------------------------------+
//| IsDoji — indecision candle, tiny body relative to range            |
//+------------------------------------------------------------------+
bool IsDoji(double body, double range)
{
   if(range == 0) return false;
   //--- Range must be meaningful (not just a flat bar)
   if(range < g_atrValue * InpDojiMinATR) return false;
   //--- Body is very small relative to range = indecision
   return (body / range <= InpDojiBodyRatio);
}

//+------------------------------------------------------------------+
//| BuildFlagString — convert wick bitmask to label text               |
//+------------------------------------------------------------------+
string BuildFlagString(int flags, bool isUpper)
{
   string result = "";
   if(flags & WICK_REJECTION)   result += "R";
   if(flags & WICK_LIQUIDITY)   result += "L";
   if(flags & WICK_FAILED_CONT) result += "F";
   if(flags & WICK_STOP_HUNT)   result += "S";
   if(flags & WICK_IMBALANCE)   result += "I";
   if(flags & WICK_SWEEP)
   {
      if(result != "") result += " ";
      result += isUpper ? "SWP\x2191" : "SWP\x2193";
   }
   if(flags & WICK_EXHAUSTION)
   {
      if(result != "") result += " ";
      result += "EXH";
   }
   return result;
}

//+------------------------------------------------------------------+
//| BuildCandleFlagString — convert candle bitmask to label text       |
//+------------------------------------------------------------------+
string BuildCandleFlagString(int flags)
{
   string result = "";
   if(flags & CANDLE_MOMENTUM) result += "MOM";
   if(flags & CANDLE_DOJI)
   {
      if(result != "") result += " ";
      result += "DOJ";
   }
   return result;
}

//+------------------------------------------------------------------+
//| GetFlagColor — color based on wick classification                  |
//+------------------------------------------------------------------+
color GetFlagColor(int flags)
{
   int count = 0;
   if(flags & WICK_REJECTION)   count++;
   if(flags & WICK_LIQUIDITY)   count++;
   if(flags & WICK_FAILED_CONT) count++;
   if(flags & WICK_STOP_HUNT)   count++;
   if(flags & WICK_IMBALANCE)   count++;
   if(flags & WICK_SWEEP)       count++;
   if(flags & WICK_EXHAUSTION)  count++;

   if(count > 1) return InpMultiColor;

   if(flags & WICK_REJECTION)   return InpRejectionColor;
   if(flags & WICK_LIQUIDITY)   return InpLiquidityColor;
   if(flags & WICK_FAILED_CONT) return InpFailedContColor;
   if(flags & WICK_STOP_HUNT)   return InpStopHuntColor;
   if(flags & WICK_IMBALANCE)   return InpImbalanceColor;
   if(flags & WICK_SWEEP)       return InpSweepColor;
   if(flags & WICK_EXHAUSTION)  return InpExhaustionColor;

   return clrGray;
}

//+------------------------------------------------------------------+
//| GetCandleFlagColor — color based on candle classification          |
//+------------------------------------------------------------------+
color GetCandleFlagColor(int flags)
{
   int count = 0;
   if(flags & CANDLE_MOMENTUM) count++;
   if(flags & CANDLE_DOJI)     count++;

   if(count > 1) return InpMultiColor;

   if(flags & CANDLE_MOMENTUM) return InpMomentumColor;
   if(flags & CANDLE_DOJI)     return InpDojiColor;

   return clrGray;
}

//+------------------------------------------------------------------+
//| DrawWickLabels — draw classification labels on chart               |
//+------------------------------------------------------------------+
void DrawWickLabels(const WickInfo &wicks[], const datetime &time[],
                    const double &open[], const double &close[],
                    const double &high[], const double &low[], int limit)
{
   double offset = g_atrValue * 0.15;
   int drawn = 0;

   for(int i = 1; i <= limit && drawn < InpMaxLabels; i++)
   {
      //--- Upper wick label
      if(InpShowUpperLabels && wicks[i].upperFlags != 0)
      {
         string text = BuildFlagString(wicks[i].upperFlags, true);
         string name = g_prefix + "U_" + IntegerToString(i);
         double yPrice = high[i] + offset;
         color clr = GetFlagColor(wicks[i].upperFlags);

         if(!ObjectCreate(0, name, OBJ_TEXT, 0, time[i], yPrice))
            ObjectMove(0, name, 0, time[i], yPrice);

         ObjectSetString(0, name, OBJPROP_TEXT, text);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
         ObjectSetDouble(0, name, OBJPROP_ANGLE, 90.0);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LOWER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         drawn++;
      }

      //--- Lower wick label
      if(InpShowLowerLabels && wicks[i].lowerFlags != 0)
      {
         string text = BuildFlagString(wicks[i].lowerFlags, false);
         string name = g_prefix + "L_" + IntegerToString(i);
         double yPrice = low[i] - offset;
         color clr = GetFlagColor(wicks[i].lowerFlags);

         if(!ObjectCreate(0, name, OBJ_TEXT, 0, time[i], yPrice))
            ObjectMove(0, name, 0, time[i], yPrice);

         ObjectSetString(0, name, OBJPROP_TEXT, text);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
         ObjectSetDouble(0, name, OBJPROP_ANGLE, 90.0);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_UPPER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         drawn++;
      }

      //--- Candle-level label (MOM / DOJ) — drawn below the candle
      if(InpShowCandleLabels && wicks[i].candleFlags != 0)
      {
         string text = BuildCandleFlagString(wicks[i].candleFlags);
         string name = g_prefix + "C_" + IntegerToString(i);
         //--- Place below lower wick label (extra offset if lower label exists)
         double extraOff = (wicks[i].lowerFlags != 0) ? offset * 2.5 : 0;
         double yPrice = low[i] - offset - extraOff;
         color clr = GetCandleFlagColor(wicks[i].candleFlags);

         if(!ObjectCreate(0, name, OBJ_TEXT, 0, time[i], yPrice))
            ObjectMove(0, name, 0, time[i], yPrice);

         ObjectSetString(0, name, OBJPROP_TEXT, text);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
         ObjectSetDouble(0, name, OBJPROP_ANGLE, 90.0);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_UPPER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         drawn++;
      }
   }
}

//+------------------------------------------------------------------+
//| CleanAllObjects                                                    |
//+------------------------------------------------------------------+
void CleanAllObjects()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_prefix) == 0)
         ObjectDelete(0, name);
   }
}
