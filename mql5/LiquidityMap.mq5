//+------------------------------------------------------------------+
//|                                                  LiquidityMap.mq5 |
//|                               TradeMind Liquidity Detection       |
//|         Detects Equal Highs/Lows, Liquidity Sweeps, Wick Pools,   |
//|         and Untapped Liquidity zones on the chart                  |
//+------------------------------------------------------------------+
#property copyright "TradeMind"
#property link      ""
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_plots 0

//+------------------------------------------------------------------+
//| Enums                                                              |
//+------------------------------------------------------------------+
enum ENUM_LIQ_TYPE
{
   LIQ_EQUAL_HIGHS = 0,  // Equal highs (buy-side liquidity)
   LIQ_EQUAL_LOWS,        // Equal lows (sell-side liquidity)
   LIQ_SWEEP_HIGH,        // Liquidity sweep above highs
   LIQ_SWEEP_LOW,         // Liquidity sweep below lows
};

enum ENUM_LIQ_STATE
{
   LIQ_UNTAPPED = 0,     // Liquidity not yet taken
   LIQ_SWEPT,             // Liquidity has been swept
};

//+------------------------------------------------------------------+
//| Input parameters                                                   |
//+------------------------------------------------------------------+
input int      InpSwingStrength      = 3;              // Swing strength (bars each side)
input int      InpMaxBars            = 500;            // Max bars to analyze
input int      InpLevelBars          = 30;             // Level line length (bars forward)
input double   InpEqualTolerance     = 0.3;            // Equal H/L tolerance (% of ATR)
input int      InpMinEqualTouches    = 2;              // Minimum touches for equal level
input int      InpATRPeriod          = 14;             // ATR period for tolerance calc

//--- Display toggles
input bool     InpShowEqualHighs     = true;           // Show equal highs (buy-side liq)
input bool     InpShowEqualLows      = true;           // Show equal lows (sell-side liq)
input bool     InpShowSweeps         = true;           // Show liquidity sweeps
input bool     InpShowWickPools      = true;           // Show wick rejection pools
input bool     InpShowSweepArrows    = true;           // Show sweep arrows
input bool     InpShowRanges         = false;          // Show liquidity ranges (consolidation zones)

//--- Color inputs
input color    InpEqualHighColor     = clrOrangeRed;   // Equal highs color
input color    InpEqualLowColor      = clrDodgerBlue;  // Equal lows color
input color    InpSweptHighColor     = clrDimGray;     // Swept high color (taken)
input color    InpSweptLowColor      = clrDimGray;     // Swept low color (taken)
input color    InpSweepArrowColor    = clrGold;        // Sweep arrow color
input color    InpWickPoolColor      = clrMediumPurple; // Wick pool color
input color    InpRangeHighColor     = clrOrangeRed;   // Range high color
input color    InpRangeLowColor      = clrDodgerBlue;  // Range low color
input color    InpRangeFillColor     = clrGold;        // Range zone fill color
input int      InpLineWidth          = 2;              // Level line width
input int      InpFontSize           = 8;              // Label font size

//+------------------------------------------------------------------+
//| Structures                                                         |
//+------------------------------------------------------------------+
struct LiquidityLevel
{
   double         price;        // Price level
   int            startBar;     // First bar that formed this level
   int            touches;      // Number of times price touched this level
   datetime       startTime;    // Time of first touch
   datetime       lastTouchTime;// Time of last touch
   ENUM_LIQ_TYPE  liqType;      // Equal high or equal low
   ENUM_LIQ_STATE state;        // Untapped or swept
   int            sweepBar;     // Bar where sweep occurred (-1 if untapped)
   datetime       sweepTime;    // Time of sweep
   double         sweepPrice;   // Wick price that swept the level
};

struct WickPool
{
   double         high;         // Upper bound of wick cluster
   double         low;          // Lower bound of wick cluster
   int            startBar;     // Oldest bar in cluster
   int            endBar;       // Newest bar in cluster
   datetime       startTime;    // Time of oldest bar
   datetime       endTime;      // Time of newest bar
   int            wickCount;    // Number of wicks in cluster
   bool           isUpperWick;  // true = upper wicks (rejection from above)
};

struct LiqRange
{
   double         high;         // Range high (resistance / buy-side liq)
   double         low;          // Range low (support / sell-side liq)
   int            startBar;     // Oldest bar in range
   int            endBar;       // Newest bar in range (0 = still active)
   datetime       startTime;    // Start time
   datetime       endTime;      // End time
   int            highTouches;  // Times price touched the high
   int            lowTouches;   // Times price touched the low
   bool           broken;       // Range has been broken
};

//+------------------------------------------------------------------+
//| Global variables                                                   |
//+------------------------------------------------------------------+
LiquidityLevel   g_liqLevels[];
int              g_liqCount = 0;

WickPool         g_wickPools[];
int              g_wickPoolCount = 0;

LiqRange         g_ranges[];
int              g_rangeCount = 0;

string           g_objPrefix = "LIQ_";
int              g_lastCalculatedBars = 0;
double           g_atrValue = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                           |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("LiquidityMap v1.0 initializing...");
   Print("Swing Strength: ", InpSwingStrength, " | Level Bars: ", InpLevelBars,
         " | Equal Tolerance: ", InpEqualTolerance, "% ATR");

   CleanAllObjects();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanAllObjects();
   Print("LiquidityMap deinitialized");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                                |
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
   //--- Only recalculate when new bar forms or first run
   if(rates_total == g_lastCalculatedBars && prev_calculated > 0)
      return rates_total;

   g_lastCalculatedBars = rates_total;

   //--- Need enough bars for ATR + analysis
   if(rates_total < InpATRPeriod + InpSwingStrength + 10)
      return rates_total;

   //--- Determine analysis range
   int barsToAnalyze = MathMin(InpMaxBars, rates_total);
   int startBar = barsToAnalyze - 1;

   //--- Clean previous objects and reset
   CleanAllObjects();
   ResetArrays();

   //--- Set arrays as series (index 0 = current bar)
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(close, true);

   //--- Calculate ATR for dynamic tolerance
   g_atrValue = CalculateATR(high, low, close, InpATRPeriod, barsToAnalyze);
   if(g_atrValue <= 0) g_atrValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100;

   //--- Step 1: Detect swing highs and lows
   double swingHighPrices[];
   int    swingHighBars[];
   datetime swingHighTimes[];
   int    swingHighCount = 0;

   double swingLowPrices[];
   int    swingLowBars[];
   datetime swingLowTimes[];
   int    swingLowCount = 0;

   DetectSwings(high, low, time, startBar,
                swingHighPrices, swingHighBars, swingHighTimes, swingHighCount,
                swingLowPrices, swingLowBars, swingLowTimes, swingLowCount);

   //--- Step 2: Find equal highs (buy-side liquidity)
   if(InpShowEqualHighs)
      FindEqualLevels(swingHighPrices, swingHighBars, swingHighTimes, swingHighCount,
                      high, low, close, time, barsToAnalyze, true);

   //--- Step 3: Find equal lows (sell-side liquidity)
   if(InpShowEqualLows)
      FindEqualLevels(swingLowPrices, swingLowBars, swingLowTimes, swingLowCount,
                      high, low, close, time, barsToAnalyze, false);

   //--- Step 4: Check for sweeps on all liquidity levels
   if(InpShowSweeps)
      DetectSweeps(high, low, close, time, barsToAnalyze);

   //--- Step 5: Detect wick rejection pools
   if(InpShowWickPools)
      DetectWickPools(open, high, low, close, time, startBar);

   //--- Step 6: Detect liquidity ranges (consolidation zones)
   if(InpShowRanges)
      DetectLiquidityRanges(high, low, close, time, startBar,
                            swingHighPrices, swingHighBars, swingHighTimes, swingHighCount,
                            swingLowPrices, swingLowBars, swingLowTimes, swingLowCount);

   //--- Step 7: Draw everything
   DrawAllObjects(time);

   return rates_total;
}

//+------------------------------------------------------------------+
//| Calculate ATR manually (no iATR handle needed)                     |
//+------------------------------------------------------------------+
double CalculateATR(const double &high[], const double &low[],
                    const double &close[], int period, int totalBars)
{
   if(totalBars < period + 1) return 0;

   double sum = 0;
   for(int i = 1; i <= period; i++)
   {
      double tr1 = high[i] - low[i];
      double tr2 = MathAbs(high[i] - close[i + 1]);
      double tr3 = MathAbs(low[i] - close[i + 1]);
      sum += MathMax(tr1, MathMax(tr2, tr3));
   }

   return sum / period;
}

//+------------------------------------------------------------------+
//| Detect swing highs and lows                                        |
//+------------------------------------------------------------------+
void DetectSwings(const double &high[], const double &low[],
                  const datetime &time[], int maxBar,
                  double &shPrices[], int &shBars[], datetime &shTimes[], int &shCount,
                  double &slPrices[], int &slBars[], datetime &slTimes[], int &slCount)
{
   shCount = 0;
   slCount = 0;

   for(int i = maxBar - InpSwingStrength; i >= InpSwingStrength; i--)
   {
      //--- Check for swing high
      bool isSwingHigh = true;
      for(int j = 1; j <= InpSwingStrength; j++)
      {
         if(high[i] <= high[i + j] || high[i] <= high[i - j])
         {
            isSwingHigh = false;
            break;
         }
      }

      if(isSwingHigh)
      {
         shCount++;
         ArrayResize(shPrices, shCount);
         ArrayResize(shBars, shCount);
         ArrayResize(shTimes, shCount);
         shPrices[shCount - 1] = high[i];
         shBars[shCount - 1]   = i;
         shTimes[shCount - 1]  = time[i];
      }

      //--- Check for swing low
      bool isSwingLow = true;
      for(int j = 1; j <= InpSwingStrength; j++)
      {
         if(low[i] >= low[i + j] || low[i] >= low[i - j])
         {
            isSwingLow = false;
            break;
         }
      }

      if(isSwingLow)
      {
         slCount++;
         ArrayResize(slPrices, slCount);
         ArrayResize(slBars, slCount);
         ArrayResize(slTimes, slCount);
         slPrices[slCount - 1] = low[i];
         slBars[slCount - 1]   = i;
         slTimes[slCount - 1]  = time[i];
      }
   }
}

//+------------------------------------------------------------------+
//| Find equal levels (highs or lows at similar prices)                |
//+------------------------------------------------------------------+
void FindEqualLevels(const double &prices[], const int &bars[],
                     const datetime &times[], int count,
                     const double &high[], const double &low[],
                     const double &close[], const datetime &time[],
                     int totalBars, bool isHighSide)
{
   if(count < 2) return;

   double tolerance = g_atrValue * (InpEqualTolerance / 100.0);
   bool used[];
   ArrayResize(used, count);
   ArrayInitialize(used, false);

   //--- Compare each swing to all subsequent swings to find clusters
   for(int i = 0; i < count; i++)
   {
      if(used[i]) continue;

      double levelPrice = prices[i];
      int    touches = 1;
      int    firstBar = bars[i];
      int    lastBar  = bars[i];
      datetime firstTime = times[i];
      datetime lastTime  = times[i];

      //--- Find all swings at similar price
      for(int j = i + 1; j < count; j++)
      {
         if(used[j]) continue;

         if(MathAbs(prices[j] - levelPrice) <= tolerance)
         {
            touches++;
            used[j] = true;

            //--- Average the level price for accuracy
            levelPrice = ((levelPrice * (touches - 1)) + prices[j]) / touches;

            //--- Update bar range (remember: higher bar index = older in series)
            if(bars[j] > firstBar)
            {
               firstBar  = bars[j];
               firstTime = times[j];
            }
            if(bars[j] < lastBar)
            {
               lastBar  = bars[j];
               lastTime = times[j];
            }
         }
      }

      //--- Only record if meets minimum touch requirement
      if(touches >= InpMinEqualTouches)
      {
         used[i] = true;

         int idx = g_liqCount;
         g_liqCount++;
         ArrayResize(g_liqLevels, g_liqCount);

         g_liqLevels[idx].price         = levelPrice;
         g_liqLevels[idx].startBar      = firstBar;
         g_liqLevels[idx].touches       = touches;
         g_liqLevels[idx].startTime     = firstTime;
         g_liqLevels[idx].lastTouchTime = lastTime;
         g_liqLevels[idx].liqType       = isHighSide ? LIQ_EQUAL_HIGHS : LIQ_EQUAL_LOWS;
         g_liqLevels[idx].state         = LIQ_UNTAPPED;
         g_liqLevels[idx].sweepBar      = -1;
         g_liqLevels[idx].sweepTime     = 0;
         g_liqLevels[idx].sweepPrice    = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Detect sweeps on liquidity levels                                  |
//+------------------------------------------------------------------+
void DetectSweeps(const double &high[], const double &low[],
                  const double &close[], const datetime &time[],
                  int totalBars)
{
   double sweepTolerance = g_atrValue * 0.05; // Small tolerance for "touching" the level

   for(int i = 0; i < g_liqCount; i++)
   {
      LiquidityLevel liq = g_liqLevels[i];

      //--- Only check bars AFTER the last touch that formed the level
      //--- In series mode: scan from lastBar towards bar 0 (newer bars)
      int scanStart = liq.startBar - 1;
      if(scanStart < 0) scanStart = 0;

      //--- Find the newest touch bar
      int newestBar = liq.startBar;
      // For equal levels, the "startBar" is the oldest. We need the newest.
      // We track lastTouchTime but need bar index. Use startBar as approximation
      // and scan forward from there.

      for(int b = scanStart; b >= 0; b--)
      {
         bool isHighSide = (liq.liqType == LIQ_EQUAL_HIGHS);

         if(isHighSide)
         {
            //--- Check if wick went above the level then closed below
            //--- This is a sweep: price pierces through to grab stops then reverses
            if(high[b] > liq.price + sweepTolerance && close[b] < liq.price)
            {
               g_liqLevels[i].state      = LIQ_SWEPT;
               g_liqLevels[i].sweepBar   = b;
               g_liqLevels[i].sweepTime  = time[b];
               g_liqLevels[i].sweepPrice = high[b];
               break;
            }
            //--- Also mark as swept if price closed above (broke through)
            if(close[b] > liq.price + sweepTolerance)
            {
               g_liqLevels[i].state      = LIQ_SWEPT;
               g_liqLevels[i].sweepBar   = b;
               g_liqLevels[i].sweepTime  = time[b];
               g_liqLevels[i].sweepPrice = high[b];
               break;
            }
         }
         else
         {
            //--- Check if wick went below the level then closed above
            if(low[b] < liq.price - sweepTolerance && close[b] > liq.price)
            {
               g_liqLevels[i].state      = LIQ_SWEPT;
               g_liqLevels[i].sweepBar   = b;
               g_liqLevels[i].sweepTime  = time[b];
               g_liqLevels[i].sweepPrice = low[b];
               break;
            }
            //--- Also mark as swept if price closed below (broke through)
            if(close[b] < liq.price - sweepTolerance)
            {
               g_liqLevels[i].state      = LIQ_SWEPT;
               g_liqLevels[i].sweepBar   = b;
               g_liqLevels[i].sweepTime  = time[b];
               g_liqLevels[i].sweepPrice = low[b];
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Detect wick rejection pools (clusters of wicks at similar prices)  |
//+------------------------------------------------------------------+
void DetectWickPools(const double &open[], const double &high[],
                     const double &low[], const double &close[],
                     const datetime &time[], int maxBar)
{
   g_wickPoolCount = 0;

   double tolerance = g_atrValue * 0.2;
   int    minWicks = 3; // Minimum wicks to form a pool

   //--- Collect significant upper wicks
   double upperWickPrices[];
   int    upperWickBars[];
   int    upperWickCount = 0;

   double lowerWickPrices[];
   int    lowerWickBars[];
   int    lowerWickCount = 0;

   for(int i = maxBar; i >= 0; i--)
   {
      double body    = MathAbs(close[i] - open[i]);
      double fullBar = high[i] - low[i];

      if(fullBar <= 0) continue;

      double upperWick = high[i] - MathMax(open[i], close[i]);
      double lowerWick = MathMin(open[i], close[i]) - low[i];

      //--- Significant upper wick: > 40% of total bar range
      if(upperWick > fullBar * 0.4)
      {
         upperWickCount++;
         ArrayResize(upperWickPrices, upperWickCount);
         ArrayResize(upperWickBars, upperWickCount);
         upperWickPrices[upperWickCount - 1] = high[i];
         upperWickBars[upperWickCount - 1]   = i;
      }

      //--- Significant lower wick: > 40% of total bar range
      if(lowerWick > fullBar * 0.4)
      {
         lowerWickCount++;
         ArrayResize(lowerWickPrices, lowerWickCount);
         ArrayResize(lowerWickBars, lowerWickCount);
         lowerWickPrices[lowerWickCount - 1] = low[i];
         lowerWickBars[lowerWickCount - 1]   = i;
      }
   }

   //--- Cluster upper wicks into pools
   ClusterWicks(upperWickPrices, upperWickBars, upperWickCount,
                tolerance, minWicks, time, true);

   //--- Cluster lower wicks into pools
   ClusterWicks(lowerWickPrices, lowerWickBars, lowerWickCount,
                tolerance, minWicks, time, false);
}

//+------------------------------------------------------------------+
//| Cluster wicks at similar prices into pools                         |
//+------------------------------------------------------------------+
void ClusterWicks(const double &prices[], const int &bars[], int count,
                  double tolerance, int minWicks, const datetime &time[],
                  bool isUpper)
{
   if(count < minWicks) return;

   bool used[];
   ArrayResize(used, count);
   ArrayInitialize(used, false);

   for(int i = 0; i < count; i++)
   {
      if(used[i]) continue;

      double clusterPrice = prices[i];
      int    wicksInCluster = 1;
      int    oldestBar = bars[i];
      int    newestBar = bars[i];

      //--- Find all wicks near this price
      for(int j = i + 1; j < count; j++)
      {
         if(used[j]) continue;

         if(MathAbs(prices[j] - clusterPrice) <= tolerance)
         {
            wicksInCluster++;
            used[j] = true;
            clusterPrice = ((clusterPrice * (wicksInCluster - 1)) + prices[j]) / wicksInCluster;

            if(bars[j] > oldestBar) oldestBar = bars[j];
            if(bars[j] < newestBar) newestBar = bars[j];
         }
      }

      if(wicksInCluster >= minWicks)
      {
         used[i] = true;

         int idx = g_wickPoolCount;
         g_wickPoolCount++;
         ArrayResize(g_wickPools, g_wickPoolCount);

         double halfTol = tolerance * 0.5;
         g_wickPools[idx].high        = clusterPrice + halfTol;
         g_wickPools[idx].low         = clusterPrice - halfTol;
         g_wickPools[idx].startBar    = oldestBar;
         g_wickPools[idx].endBar      = newestBar;
         g_wickPools[idx].startTime   = time[oldestBar];
         g_wickPools[idx].endTime     = time[newestBar];
         g_wickPools[idx].wickCount   = wicksInCluster;
         g_wickPools[idx].isUpperWick = isUpper;
      }
   }
}

//+------------------------------------------------------------------+
//| Detect liquidity ranges (price consolidating between levels)       |
//+------------------------------------------------------------------+
void DetectLiquidityRanges(const double &high[], const double &low[],
                           const double &close[], const datetime &time[],
                           int maxBar,
                           const double &shPrices[], const int &shBars[],
                           const datetime &shTimes[], int shCount,
                           const double &slPrices[], const int &slBars[],
                           const datetime &slTimes[], int slCount)
{
   g_rangeCount = 0;

   if(shCount < 2 || slCount < 2) return;

   double tolerance = g_atrValue * (InpEqualTolerance / 100.0);

   //--- Strategy: find pairs of swing highs at similar price AND
   //--- swing lows at similar price that overlap in time = range zone.
   //--- Walk through swing highs looking for resistance clusters
   for(int i = 0; i < shCount - 1; i++)
   {
      //--- Check if next swing high is at a similar level (resistance cluster)
      if(MathAbs(shPrices[i] - shPrices[i + 1]) > tolerance * 5)
         continue;

      double rangeHigh = MathMax(shPrices[i], shPrices[i + 1]);
      int    rangeOldestBar = MathMax(shBars[i], shBars[i + 1]); // Higher index = older in series
      int    rangeNewestBar = MathMin(shBars[i], shBars[i + 1]);
      int    highTouches = 2;

      //--- Find swing lows within this bar span that form the range floor
      double rangeLow = 999999;
      int    lowTouches = 0;

      for(int j = 0; j < slCount; j++)
      {
         //--- Swing low must be within the time span of the range (with some margin)
         if(slBars[j] <= rangeOldestBar + InpSwingStrength &&
            slBars[j] >= rangeNewestBar - InpSwingStrength)
         {
            if(rangeLow >= 999999)
            {
               rangeLow = slPrices[j];
               lowTouches = 1;
            }
            else if(MathAbs(slPrices[j] - rangeLow) <= tolerance * 5)
            {
               rangeLow = MathMin(rangeLow, slPrices[j]);
               lowTouches++;
            }
         }
      }

      //--- Need at least 1 low to form a range
      if(rangeLow >= 999999 || lowTouches < 1) continue;

      //--- Validate range width: not too thin, not too wide
      double rangeWidth = rangeHigh - rangeLow;
      if(rangeWidth <= 0) continue;
      if(rangeWidth > g_atrValue * 3) continue; // Too wide = not a consolidation

      //--- Validate that price was mostly contained within the range
      int barsContained = 0;
      int barsTested = 0;
      for(int b = rangeOldestBar; b >= rangeNewestBar && b >= 0; b--)
      {
         barsTested++;
         if(high[b] <= rangeHigh + tolerance && low[b] >= rangeLow - tolerance)
            barsContained++;
      }

      //--- At least 60% of bars should be inside the range
      if(barsTested < 3) continue;
      double containment = (double)barsContained / barsTested;
      if(containment < 0.6) continue;

      //--- Check if range has been broken (scan bars after the range)
      bool broken = false;
      int breakBar = -1;
      for(int b = rangeNewestBar - 1; b >= 0; b--)
      {
         if(close[b] > rangeHigh + tolerance || close[b] < rangeLow - tolerance)
         {
            broken = true;
            breakBar = b;
            break;
         }
      }

      //--- Store the range
      int idx = g_rangeCount;
      g_rangeCount++;
      ArrayResize(g_ranges, g_rangeCount);

      g_ranges[idx].high        = rangeHigh;
      g_ranges[idx].low         = rangeLow;
      g_ranges[idx].startBar    = rangeOldestBar;
      g_ranges[idx].endBar      = broken ? breakBar : 0;
      g_ranges[idx].startTime   = time[rangeOldestBar];
      g_ranges[idx].endTime     = broken ? time[breakBar] : time[0];
      g_ranges[idx].highTouches = highTouches;
      g_ranges[idx].lowTouches  = lowTouches;
      g_ranges[idx].broken      = broken;
   }
}

//+------------------------------------------------------------------+
//| Draw all visual objects on chart                                    |
//+------------------------------------------------------------------+
void DrawAllObjects(const datetime &time[])
{
   int totalBars = ArraySize(time);

   //--- Draw liquidity levels (equal highs/lows)
   DrawLiquidityLevels(time, totalBars);

   //--- Draw wick pools
   if(InpShowWickPools)
      DrawWickPools(time, totalBars);

   //--- Draw liquidity ranges
   if(InpShowRanges)
      DrawLiquidityRanges(time, totalBars);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw liquidity levels with status (untapped / swept)               |
//+------------------------------------------------------------------+
void DrawLiquidityLevels(const datetime &time[], int totalBars)
{
   for(int i = 0; i < g_liqCount; i++)
   {
      LiquidityLevel liq = g_liqLevels[i];
      bool isHighSide = (liq.liqType == LIQ_EQUAL_HIGHS);
      bool isSwept    = (liq.state == LIQ_SWEPT);

      //--- Determine color based on type and state
      color lineColor;
      if(isSwept)
         lineColor = isHighSide ? InpSweptHighColor : InpSweptLowColor;
      else
         lineColor = isHighSide ? InpEqualHighColor : InpEqualLowColor;

      //--- Line style: solid for untapped, dot for swept
      ENUM_LINE_STYLE lineStyle = isSwept ? STYLE_DOT : STYLE_SOLID;
      int lineWidth = isSwept ? 1 : InpLineWidth;

      //--- Calculate line endpoints
      int lineStartBar = liq.startBar;
      int lineEndBar;

      if(isSwept)
      {
         //--- End line at the sweep bar
         lineEndBar = MathMax(liq.sweepBar, 0);
      }
      else
      {
         //--- Extend from last touch forward by InpLevelBars
         lineEndBar = 0; // Extend to current bar (untapped = still active)
      }

      //--- Clamp to bounds
      if(lineStartBar >= totalBars) lineStartBar = totalBars - 1;
      if(lineEndBar >= totalBars)   lineEndBar = totalBars - 1;
      if(lineStartBar < 0) lineStartBar = 0;
      if(lineEndBar < 0)   lineEndBar = 0;

      //--- Draw the level line
      string lineName = g_objPrefix + "LV_" + IntegerToString(i);
      DrawHorizontalLine(lineName, time[lineStartBar], time[lineEndBar],
                        liq.price, lineColor, lineWidth, lineStyle);

      //--- Draw label
      string labelText;
      if(isHighSide)
         labelText = "EQH x" + IntegerToString(liq.touches);
      else
         labelText = "EQL x" + IntegerToString(liq.touches);

      if(isSwept)
         labelText = labelText + " (swept)";

      string labelName = g_objPrefix + "LB_" + IntegerToString(i);
      DrawLabel(labelName, time[lineStartBar], liq.price,
                labelText, lineColor, isHighSide, InpFontSize);

      //--- Draw sweep arrow if applicable
      if(isSwept && InpShowSweepArrows && liq.sweepBar >= 0 && liq.sweepBar < totalBars)
      {
         string arrowName = g_objPrefix + "SW_" + IntegerToString(i);
         DrawSweepArrow(arrowName, liq.sweepTime, liq.sweepPrice, isHighSide);

         //--- Draw "SWEEP" label near the arrow
         string sweepLabel = g_objPrefix + "SL_" + IntegerToString(i);
         DrawLabel(sweepLabel, liq.sweepTime, liq.sweepPrice,
                  "SWEEP", InpSweepArrowColor, isHighSide, InpFontSize - 1);
      }
   }
}

//+------------------------------------------------------------------+
//| Draw wick rejection pools as shaded zones                          |
//+------------------------------------------------------------------+
void DrawWickPools(const datetime &time[], int totalBars)
{
   for(int i = 0; i < g_wickPoolCount; i++)
   {
      WickPool pool = g_wickPools[i];

      //--- Extend zone forward from newest bar by InpLevelBars
      int endBar = MathMax(pool.endBar - InpLevelBars, 0);
      int startBar = pool.startBar;

      if(startBar >= totalBars) startBar = totalBars - 1;
      if(endBar >= totalBars)   endBar = totalBars - 1;

      //--- Draw rectangle for the wick pool zone
      string rectName = g_objPrefix + "WP_" + IntegerToString(i);

      if(!ObjectCreate(0, rectName, OBJ_RECTANGLE, 0,
                       time[startBar], pool.high,
                       time[endBar], pool.low))
         continue;

      ObjectSetInteger(0, rectName, OBJPROP_COLOR, InpWickPoolColor);
      ObjectSetInteger(0, rectName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
      ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
      ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, rectName, OBJPROP_HIDDEN, true);

      //--- Label
      string labelText = (pool.isUpperWick ? "Wick Pool " : "Wick Pool ");
      labelText += IntegerToString(pool.wickCount) + "x";

      string labelName = g_objPrefix + "WL_" + IntegerToString(i);
      DrawLabel(labelName, time[startBar], pool.isUpperWick ? pool.high : pool.low,
                labelText, InpWickPoolColor, pool.isUpperWick, InpFontSize - 1);
   }
}

//+------------------------------------------------------------------+
//| Draw liquidity ranges as rectangles with H/L lines                 |
//+------------------------------------------------------------------+
void DrawLiquidityRanges(const datetime &time[], int totalBars)
{
   for(int i = 0; i < g_rangeCount; i++)
   {
      LiqRange rng = g_ranges[i];

      int startBar = rng.startBar;
      int endBar   = rng.endBar;
      if(startBar >= totalBars) startBar = totalBars - 1;
      if(endBar >= totalBars)   endBar = totalBars - 1;

      //--- Draw filled rectangle for the range zone
      string rectName = g_objPrefix + "RNG_" + IntegerToString(i);
      if(ObjectCreate(0, rectName, OBJ_RECTANGLE, 0,
                       time[startBar], rng.high,
                       time[endBar], rng.low))
      {
         ObjectSetInteger(0, rectName, OBJPROP_COLOR, InpRangeFillColor);
         ObjectSetInteger(0, rectName, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
         ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
         ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, rectName, OBJPROP_HIDDEN, true);
      }

      //--- Draw range high line
      string highLineName = g_objPrefix + "RH_" + IntegerToString(i);
      DrawHorizontalLine(highLineName, time[startBar], time[endBar],
                        rng.high, InpRangeHighColor, InpLineWidth, STYLE_SOLID);

      //--- Draw range low line
      string lowLineName = g_objPrefix + "RL_" + IntegerToString(i);
      DrawHorizontalLine(lowLineName, time[startBar], time[endBar],
                        rng.low, InpRangeLowColor, InpLineWidth, STYLE_SOLID);

      //--- Labels
      string highLabel = "Range H";
      string lowLabel  = "Range L";

      string hlName = g_objPrefix + "RHL_" + IntegerToString(i);
      DrawLabel(hlName, time[startBar], rng.high,
                highLabel, InpRangeHighColor, true, InpFontSize);

      string llName = g_objPrefix + "RLL_" + IntegerToString(i);
      DrawLabel(llName, time[startBar], rng.low,
                lowLabel, InpRangeLowColor, false, InpFontSize);
   }
}

//+------------------------------------------------------------------+
//| Helper: Draw a text label on the chart                             |
//+------------------------------------------------------------------+
void DrawLabel(string name, datetime labelTime, double price,
               string text, color clr, bool above, int fontSize)
{
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, labelTime, price))
   {
      ObjectMove(0, name, 0, labelTime, price);
   }

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, above ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Helper: Draw a horizontal line segment between two times           |
//+------------------------------------------------------------------+
void DrawHorizontalLine(string name, datetime time1, datetime time2,
                        double price, color clr, int width,
                        ENUM_LINE_STYLE style)
{
   if(!ObjectCreate(0, name, OBJ_TREND, 0, time1, price, time2, price))
   {
      ObjectMove(0, name, 0, time1, price);
      ObjectMove(0, name, 1, time2, price);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Helper: Draw sweep arrow                                           |
//+------------------------------------------------------------------+
void DrawSweepArrow(string name, datetime arrowTime, double price, bool isHighSide)
{
   //--- Arrow pointing down for high sweep, up for low sweep
   int arrowCode = isHighSide ? 234 : 233; // Wingdings: down/up arrow

   if(!ObjectCreate(0, name, OBJ_ARROW, 0, arrowTime, price))
   {
      ObjectMove(0, name, 0, arrowTime, price);
   }

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpSweepArrowColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isHighSide ? ANCHOR_BOTTOM : ANCHOR_TOP);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Clean all indicator objects from the chart                         |
//+------------------------------------------------------------------+
void CleanAllObjects()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_objPrefix) == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| Reset all data arrays                                              |
//+------------------------------------------------------------------+
void ResetArrays()
{
   g_liqCount      = 0;
   g_wickPoolCount = 0;
   g_rangeCount    = 0;

   ArrayResize(g_liqLevels, 0);
   ArrayResize(g_wickPools, 0);
   ArrayResize(g_ranges, 0);
}
//+------------------------------------------------------------------+
