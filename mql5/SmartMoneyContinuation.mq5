//+------------------------------------------------------------------+
//|                                      SmartMoneyContinuation.mq5  |
//|                           TradeMind Smart Money Continuation      |
//|      Rule-based continuation model after liquidity sweeps.        |
//|      Detects sweeps, checks 3 conditions, generates signals.      |
//|      Classifies sweep context: Range (fuel) vs HTF Extreme        |
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
enum ENUM_SWEEP_DIR
{
   SWEEP_BULLISH = 0,   // Bullish (sweep below lows → expect move up)
   SWEEP_BEARISH,        // Bearish (sweep above highs → expect move down)
};

enum ENUM_SWEEP_CONTEXT
{
   CTX_RANGE_SWEEP = 0, // Range sweep — fuel for continuation
   CTX_HTF_EXTREME,      // HTF extreme sweep — reversal caution
   CTX_UNKNOWN,          // Context not classified
};

enum ENUM_SIGNAL_STATE
{
   STATE_SWEEP_DETECTED = 0,  // Sweep found, checking conditions
   STATE_STRUCTURE_HELD,       // Step 1 passed: no CHoCH against trend
   STATE_DISPLACED,            // Step 2 passed: displacement candle found
   STATE_ZONE_RESPECTED,       // Step 3 passed: pullback respected OB → SIGNAL
   STATE_INVALIDATED,          // Failed: structure broke or zone broken
};

//+------------------------------------------------------------------+
//| Structures                                                         |
//+------------------------------------------------------------------+
struct SwingPoint
{
   int            bar;
   double         price;
   bool           isHigh;
   datetime       time;
};

struct SweepEvent
{
   //--- Sweep detection
   int            bar;              // Bar where sweep occurred
   datetime       time;             // Time of sweep
   double         levelPrice;       // The level that was swept
   double         sweepPrice;       // Wick price (actual sweep extent)
   ENUM_SWEEP_DIR direction;        // Bullish or bearish bias
   ENUM_SWEEP_CONTEXT context;      // Range fuel vs HTF extreme
   ENUM_SIGNAL_STATE  state;        // Current checklist state

   //--- Step 1: Structure
   bool           chochOccurred;    // Did CHoCH happen against the trend?

   //--- Step 2: Displacement
   int            displacementBar;
   datetime       displacementTime;
   double         displacementClose;

   //--- Order Block (from displacement)
   int            obStartBar;
   int            obEndBar;
   double         obHigh;
   double         obLow;
   datetime       obStartTime;
   datetime       obEndTime;

   //--- Step 3: Signal
   int            signalBar;
   datetime       signalTime;
};

struct EqualLevel
{
   double         price;            // Average price of equal level
   int            startBar;         // Oldest bar in cluster
   int            endBar;           // Newest bar in cluster (for line extension)
   datetime       startTime;        // Time of oldest bar
   datetime       endTime;          // Time of newest bar
   int            touches;          // Number of touches
   bool           isHigh;           // true = equal highs, false = equal lows
   bool           swept;            // Has this level been swept?
   int            sweepBar;         // Bar where sweep occurred
   datetime       sweepTime;        // Time of sweep
};

//+------------------------------------------------------------------+
//| Input parameters                                                   |
//+------------------------------------------------------------------+
//--- Detection
input int      InpSwingStrength      = 5;              // Swing strength (bars each side)
input int      InpHTFSwingStrength   = 10;             // HTF extreme swing strength (larger)
input int      InpMaxBars            = 500;            // Max bars to analyze
input int      InpLevelBars          = 20;             // Zone forward extension (bars)
input double   InpDisplacementRatio  = 0.7;            // Min body/range for displacement candle
input int      InpATRPeriod          = 14;             // ATR period
input double   InpEqualTolerance     = 0.3;            // Equal level tolerance (x ATR, e.g. 0.3 = 30% of ATR)
input int      InpMaxBarsAfterSweep  = 20;             // Window to find displacement after sweep
input int      InpMaxBarsPullback    = 30;             // Window to find pullback after displacement

//--- Toggles
input bool     InpShowSweepArrows    = true;           // Show sweep arrows
input bool     InpShowDisplacement   = true;           // Show displacement markers
input bool     InpShowZones          = true;           // Show order block zones
input bool     InpShowSignals        = true;           // Show continuation signals
input bool     InpShowContextLabels  = true;           // Show context labels (Fuel / Caution)
input bool     InpShowDashboard      = true;           // Show dashboard (Comment)
input bool     InpShowEqualHighs     = true;           // Show equal highs (buy-side liquidity)
input bool     InpShowEqualLows      = true;           // Show equal lows (sell-side liquidity)
input int      InpMinEqualTouches    = 2;              // Minimum touches for equal level

//--- Colors
input color    InpSweepArrowColor    = clrGold;        // Sweep arrow color
input color    InpDisplaceBullColor  = clrLime;        // Bullish displacement color
input color    InpDisplaceBearColor  = clrRed;         // Bearish displacement color
input color    InpDemandZoneColor    = clrDodgerBlue;  // Demand zone (OB) color
input color    InpSupplyZoneColor    = clrCrimson;     // Supply zone (OB) color
input color    InpSignalBullColor    = clrLime;        // Bullish signal color
input color    InpSignalBearColor    = clrRed;         // Bearish signal color
input color    InpContextFuelColor   = clrGold;        // Context: fuel label color
input color    InpContextCautionColor = clrOrangeRed;  // Context: caution label color
input color    InpEqualHighColor     = clrOrangeRed;   // Equal highs color (untapped)
input color    InpEqualLowColor      = clrDodgerBlue;  // Equal lows color (untapped)
input color    InpEqualSweptColor    = clrDimGray;     // Swept equal level color
input int      InpEqualLineWidth     = 2;              // Equal level line width
input int      InpFontSize           = 8;              // Label font size

//+------------------------------------------------------------------+
//| Global variables                                                   |
//+------------------------------------------------------------------+
SwingPoint       g_swingHighs[];
SwingPoint       g_swingLows[];
int              g_swingHighCount = 0;
int              g_swingLowCount  = 0;

SwingPoint       g_htfSwingHighs[];
SwingPoint       g_htfSwingLows[];
int              g_htfSwingHighCount = 0;
int              g_htfSwingLowCount  = 0;

SweepEvent       g_sweeps[];
int              g_sweepCount = 0;

EqualLevel       g_equalLevels[];
int              g_equalLevelCount = 0;

string           g_objPrefix = "SMC_";
int              g_lastCalculatedBars = 0;
double           g_atrValue = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                           |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("SmartMoneyContinuation v1.0 initializing...");
   Print("Swing: ", InpSwingStrength, " | HTF: ", InpHTFSwingStrength,
         " | Displacement: ", DoubleToString(InpDisplacementRatio, 1),
         " | ATR: ", InpATRPeriod);

   CleanAllObjects();
   Comment("");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanAllObjects();
   Comment("");
   Print("SmartMoneyContinuation deinitialized");
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

   //--- Need enough bars
   if(rates_total < InpATRPeriod + InpHTFSwingStrength + 10)
      return rates_total;

   //--- Determine analysis range
   int barsToAnalyze = MathMin(InpMaxBars, rates_total);
   int startBar = barsToAnalyze - 1;

   //--- Clean and reset
   CleanAllObjects();
   ResetArrays();

   //--- Set arrays as series (index 0 = current bar)
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(close, true);

   //--- 1. Calculate ATR
   g_atrValue = CalculateATR(high, low, close, InpATRPeriod, barsToAnalyze);
   if(g_atrValue <= 0) g_atrValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100;

   //--- 2. Detect swing points (normal strength)
   DetectSwingPoints(high, low, time, startBar, InpSwingStrength,
                     g_swingHighs, g_swingHighCount,
                     g_swingLows, g_swingLowCount);

   //--- 3. Detect HTF swing points (larger strength)
   DetectSwingPoints(high, low, time, startBar, InpHTFSwingStrength,
                     g_htfSwingHighs, g_htfSwingHighCount,
                     g_htfSwingLows, g_htfSwingLowCount);

   //--- 4. Detect equal highs and lows (liquidity levels)
   if(InpShowEqualHighs || InpShowEqualLows)
      DetectEqualLevels(high, low, close, time, startBar);

   //--- 5. Detect sweeps (price wicking through levels and closing back)
   DetectSweeps(high, low, close, time, startBar);

   //--- 6. Classify sweep context (range fuel vs HTF extreme)
   ClassifySweepContext();

   //--- 7. Run 3-step model for each sweep
   for(int i = 0; i < g_sweepCount; i++)
   {
      if(g_sweeps[i].state == STATE_INVALIDATED)
         continue;

      //--- Step 1: Check post-sweep structure (no CHoCH against trend)
      CheckPostSweepStructure(i, high, low, close, time, startBar);
      if(g_sweeps[i].state == STATE_INVALIDATED)
         continue;

      //--- Step 2: Detect displacement candle
      DetectDisplacement(i, open, high, low, close, time, startBar);
      if(g_sweeps[i].state < STATE_DISPLACED)
         continue;

      //--- Identify order block from displacement origin
      IdentifyOrderBlock(i, open, high, low, close, time, startBar);

      //--- Step 3: Check pullback respect of the OB zone
      CheckPullbackRespect(i, high, low, close, time, startBar);
   }

   //--- 8. Draw everything
   DrawAllObjects(time, high, low);

   //--- 9. Build dashboard
   if(InpShowDashboard)
      BuildDashboard();

   return rates_total;
}

//+------------------------------------------------------------------+
//| Calculate ATR manually                                             |
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
//| Detect swing highs and lows with parameterized strength            |
//+------------------------------------------------------------------+
void DetectSwingPoints(const double &high[], const double &low[],
                       const datetime &time[], int maxBar, int strength,
                       SwingPoint &swingHighs[], int &highCount,
                       SwingPoint &swingLows[], int &lowCount)
{
   highCount = 0;
   lowCount  = 0;

   for(int i = maxBar - strength; i >= strength; i--)
   {
      //--- Check for swing high
      bool isSwingHigh = true;
      for(int j = 1; j <= strength; j++)
      {
         if(high[i] <= high[i + j] || high[i] <= high[i - j])
         {
            isSwingHigh = false;
            break;
         }
      }

      if(isSwingHigh)
      {
         int idx = highCount;
         highCount++;
         ArrayResize(swingHighs, highCount);
         swingHighs[idx].bar    = i;
         swingHighs[idx].price  = high[i];
         swingHighs[idx].isHigh = true;
         swingHighs[idx].time   = time[i];
      }

      //--- Check for swing low
      bool isSwingLow = true;
      for(int j = 1; j <= strength; j++)
      {
         if(low[i] >= low[i + j] || low[i] >= low[i - j])
         {
            isSwingLow = false;
            break;
         }
      }

      if(isSwingLow)
      {
         int idx = lowCount;
         lowCount++;
         ArrayResize(swingLows, lowCount);
         swingLows[idx].bar    = i;
         swingLows[idx].price  = low[i];
         swingLows[idx].isHigh = false;
         swingLows[idx].time   = time[i];
      }
   }
}

//+------------------------------------------------------------------+
//| Detect equal highs and lows (liquidity levels from ALL wicks)     |
//| Scans bar highs/lows within InpMaxBars to find price clusters      |
//+------------------------------------------------------------------+
void DetectEqualLevels(const double &high[], const double &low[],
                       const double &close[], const datetime &time[],
                       int maxBar)
{
   g_equalLevelCount = 0;

   double tolerance = g_atrValue * InpEqualTolerance;  // ATR-based tolerance for clustering
   double sweepTol  = g_atrValue * 0.05;

   //--- Minimum gap between bars to count as separate touches
   //--- (prevents clustering adjacent bars as multiple touches)
   int minBarGap = 3;

   //--- Only analyze within InpMaxBars (maxBar is already clamped to this)
   int analyzeStart = maxBar;  // Oldest bar to analyze
   int analyzeEnd = 0;         // Newest bar (current)

   //--- Detect equal highs from bar wicks within range
   if(InpShowEqualHighs)
   {
      bool used[];
      ArrayResize(used, analyzeStart + 1);
      ArrayInitialize(used, false);

      for(int i = analyzeStart; i >= analyzeEnd; i--)
      {
         if(used[i]) continue;

         double levelPrice = high[i];
         int touches = 1;
         int oldestBar = i;
         int newestBar = i;
         datetime oldestTime = time[i];
         datetime newestTime = time[i];
         int lastTouchBar = i;

         //--- Find all bars with highs at similar price (within analysis range)
         for(int j = i - 1; j >= analyzeEnd; j--)
         {
            if(used[j]) continue;

            if(MathAbs(high[j] - levelPrice) <= tolerance)
            {
               //--- Enforce minimum gap between touches
               if(MathAbs(j - lastTouchBar) >= minBarGap)
               {
                  touches++;
                  used[j] = true;
                  levelPrice = ((levelPrice * (touches - 1)) + high[j]) / touches;
                  lastTouchBar = j;

                  if(j > oldestBar)
                  {
                     oldestBar = j;
                     oldestTime = time[j];
                  }
                  if(j < newestBar)
                  {
                     newestBar = j;
                     newestTime = time[j];
                  }
               }
            }
         }

         if(touches >= InpMinEqualTouches)
         {
            used[i] = true;
            int idx = g_equalLevelCount;
            g_equalLevelCount++;
            ArrayResize(g_equalLevels, g_equalLevelCount);

            g_equalLevels[idx].price     = levelPrice;
            g_equalLevels[idx].startBar  = oldestBar;
            g_equalLevels[idx].endBar    = newestBar;
            g_equalLevels[idx].startTime = oldestTime;
            g_equalLevels[idx].endTime   = newestTime;
            g_equalLevels[idx].touches   = touches;
            g_equalLevels[idx].isHigh    = true;
            g_equalLevels[idx].swept     = false;
            g_equalLevels[idx].sweepBar  = -1;
            g_equalLevels[idx].sweepTime = 0;

            //--- Check if this level has been swept (within analysis range)
            for(int b = newestBar - 1; b >= analyzeEnd; b--)
            {
               //--- Sweep = wick above level + close below level
               if(high[b] > levelPrice + sweepTol && close[b] < levelPrice)
               {
                  g_equalLevels[idx].swept     = true;
                  g_equalLevels[idx].sweepBar  = b;
                  g_equalLevels[idx].sweepTime = time[b];
                  break;
               }
               //--- Or price closed clearly above (broke through)
               if(close[b] > levelPrice + sweepTol)
               {
                  g_equalLevels[idx].swept     = true;
                  g_equalLevels[idx].sweepBar  = b;
                  g_equalLevels[idx].sweepTime = time[b];
                  break;
               }
            }
         }
      }
   }

   //--- Detect equal lows from bar wicks within range
   if(InpShowEqualLows)
   {
      bool used[];
      ArrayResize(used, analyzeStart + 1);
      ArrayInitialize(used, false);

      for(int i = analyzeStart; i >= analyzeEnd; i--)
      {
         if(used[i]) continue;

         double levelPrice = low[i];
         int touches = 1;
         int oldestBar = i;
         int newestBar = i;
         datetime oldestTime = time[i];
         datetime newestTime = time[i];
         int lastTouchBar = i;

         //--- Find all bars with lows at similar price (within analysis range)
         for(int j = i - 1; j >= analyzeEnd; j--)
         {
            if(used[j]) continue;

            if(MathAbs(low[j] - levelPrice) <= tolerance)
            {
               //--- Enforce minimum gap between touches
               if(MathAbs(j - lastTouchBar) >= minBarGap)
               {
                  touches++;
                  used[j] = true;
                  levelPrice = ((levelPrice * (touches - 1)) + low[j]) / touches;
                  lastTouchBar = j;

                  if(j > oldestBar)
                  {
                     oldestBar = j;
                     oldestTime = time[j];
                  }
                  if(j < newestBar)
                  {
                     newestBar = j;
                     newestTime = time[j];
                  }
               }
            }
         }

         if(touches >= InpMinEqualTouches)
         {
            used[i] = true;
            int idx = g_equalLevelCount;
            g_equalLevelCount++;
            ArrayResize(g_equalLevels, g_equalLevelCount);

            g_equalLevels[idx].price     = levelPrice;
            g_equalLevels[idx].startBar  = oldestBar;
            g_equalLevels[idx].endBar    = newestBar;
            g_equalLevels[idx].startTime = oldestTime;
            g_equalLevels[idx].endTime   = newestTime;
            g_equalLevels[idx].touches   = touches;
            g_equalLevels[idx].isHigh    = false;
            g_equalLevels[idx].swept     = false;
            g_equalLevels[idx].sweepBar  = -1;
            g_equalLevels[idx].sweepTime = 0;

            //--- Check if this level has been swept (within analysis range)
            for(int b = newestBar - 1; b >= analyzeEnd; b--)
            {
               //--- Sweep = wick below level + close above level
               if(low[b] < levelPrice - sweepTol && close[b] > levelPrice)
               {
                  g_equalLevels[idx].swept     = true;
                  g_equalLevels[idx].sweepBar  = b;
                  g_equalLevels[idx].sweepTime = time[b];
                  break;
               }
               //--- Or price closed clearly below (broke through)
               if(close[b] < levelPrice - sweepTol)
               {
                  g_equalLevels[idx].swept     = true;
                  g_equalLevels[idx].sweepBar  = b;
                  g_equalLevels[idx].sweepTime = time[b];
                  break;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Detect sweeps: price wicking through equal/swing levels            |
//+------------------------------------------------------------------+
void DetectSweeps(const double &high[], const double &low[],
                  const double &close[], const datetime &time[],
                  int maxBar)
{
   g_sweepCount = 0;

   double tolerance = g_atrValue * (InpEqualTolerance / 100.0);
   double sweepTol  = g_atrValue * 0.05;
   double dedupPrice = g_atrValue * 0.2;

   //--- Cluster swing highs into equal-high levels
   double eqHighPrices[];
   int    eqHighBars[];      // Newest bar in cluster (for scanning forward)
   int    eqHighCount = 0;

   ClusterSwingLevels(g_swingHighs, g_swingHighCount, tolerance,
                      eqHighPrices, eqHighBars, eqHighCount);

   //--- Cluster swing lows into equal-low levels
   double eqLowPrices[];
   int    eqLowBars[];
   int    eqLowCount = 0;

   ClusterSwingLevels(g_swingLows, g_swingLowCount, tolerance,
                      eqLowPrices, eqLowBars, eqLowCount);

   //--- Also add standalone significant swings as sweep-able levels
   AddStandaloneSwings(g_swingHighs, g_swingHighCount, eqHighPrices, eqHighBars, eqHighCount, tolerance);
   AddStandaloneSwings(g_swingLows, g_swingLowCount, eqLowPrices, eqLowBars, eqLowCount, tolerance);

   //--- Scan for sweeps of equal highs (bearish sweep: wick above, close below)
   for(int i = 0; i < eqHighCount; i++)
   {
      int scanStart = eqHighBars[i] - 1;
      if(scanStart < 0) scanStart = 0;

      for(int b = scanStart; b >= 0; b--)
      {
         //--- Wick above level + close below = sweep
         if(high[b] > eqHighPrices[i] + sweepTol && close[b] < eqHighPrices[i])
         {
            //--- Deduplicate: skip if a similar sweep already exists
            if(!IsDuplicateSweep(b, eqHighPrices[i], dedupPrice))
            {
               AddSweep(b, time[b], eqHighPrices[i], high[b], SWEEP_BEARISH);
            }
            break;
         }
      }
   }

   //--- Scan for sweeps of equal lows (bullish sweep: wick below, close above)
   for(int i = 0; i < eqLowCount; i++)
   {
      int scanStart = eqLowBars[i] - 1;
      if(scanStart < 0) scanStart = 0;

      for(int b = scanStart; b >= 0; b--)
      {
         //--- Wick below level + close above = sweep
         if(low[b] < eqLowPrices[i] - sweepTol && close[b] > eqLowPrices[i])
         {
            if(!IsDuplicateSweep(b, eqLowPrices[i], dedupPrice))
            {
               AddSweep(b, time[b], eqLowPrices[i], low[b], SWEEP_BULLISH);
            }
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cluster swing points at similar prices into equal levels           |
//+------------------------------------------------------------------+
void ClusterSwingLevels(const SwingPoint &swings[], int count,
                        double tolerance,
                        double &prices[], int &bars[], int &outCount)
{
   outCount = 0;
   if(count < 2) return;

   bool used[];
   ArrayResize(used, count);
   ArrayInitialize(used, false);

   for(int i = 0; i < count; i++)
   {
      if(used[i]) continue;

      double avgPrice = swings[i].price;
      int    newestBar = swings[i].bar;  // Lowest bar index = newest in series
      int    touches = 1;

      for(int j = i + 1; j < count; j++)
      {
         if(used[j]) continue;

         if(MathAbs(swings[j].price - avgPrice) <= tolerance)
         {
            touches++;
            used[j] = true;
            avgPrice = ((avgPrice * (touches - 1)) + swings[j].price) / touches;

            if(swings[j].bar < newestBar)
               newestBar = swings[j].bar;
         }
      }

      //--- Need at least 2 touches to form equal level
      if(touches >= 2)
      {
         used[i] = true;
         int idx = outCount;
         outCount++;
         ArrayResize(prices, outCount);
         ArrayResize(bars, outCount);
         prices[idx] = avgPrice;
         bars[idx]   = newestBar;
      }
   }
}

//+------------------------------------------------------------------+
//| Add standalone significant swings as sweep-able levels             |
//+------------------------------------------------------------------+
void AddStandaloneSwings(const SwingPoint &swings[], int count,
                         double &prices[], int &bars[], int &outCount,
                         double tolerance)
{
   for(int i = 0; i < count; i++)
   {
      //--- Check this swing isn't already part of a clustered level
      bool alreadyClustered = false;
      for(int j = 0; j < outCount; j++)
      {
         if(MathAbs(swings[i].price - prices[j]) <= tolerance * 2)
         {
            alreadyClustered = true;
            break;
         }
      }

      if(!alreadyClustered)
      {
         int idx = outCount;
         outCount++;
         ArrayResize(prices, outCount);
         ArrayResize(bars, outCount);
         prices[idx] = swings[i].price;
         bars[idx]   = swings[i].bar;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if a sweep already exists nearby (deduplication)             |
//+------------------------------------------------------------------+
bool IsDuplicateSweep(int bar, double price, double priceTol)
{
   for(int i = 0; i < g_sweepCount; i++)
   {
      if(MathAbs(g_sweeps[i].bar - bar) <= 3 &&
         MathAbs(g_sweeps[i].levelPrice - price) <= priceTol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Add a sweep event to the array                                     |
//+------------------------------------------------------------------+
void AddSweep(int bar, datetime sweepTime, double levelPrice,
              double sweepPrice, ENUM_SWEEP_DIR direction)
{
   int idx = g_sweepCount;
   g_sweepCount++;
   ArrayResize(g_sweeps, g_sweepCount);

   g_sweeps[idx].bar              = bar;
   g_sweeps[idx].time             = sweepTime;
   g_sweeps[idx].levelPrice       = levelPrice;
   g_sweeps[idx].sweepPrice       = sweepPrice;
   g_sweeps[idx].direction        = direction;
   g_sweeps[idx].context          = CTX_UNKNOWN;
   g_sweeps[idx].state            = STATE_SWEEP_DETECTED;
   g_sweeps[idx].chochOccurred    = false;
   g_sweeps[idx].displacementBar  = -1;
   g_sweeps[idx].displacementTime = 0;
   g_sweeps[idx].displacementClose = 0;
   g_sweeps[idx].obStartBar       = -1;
   g_sweeps[idx].obEndBar         = -1;
   g_sweeps[idx].obHigh           = 0;
   g_sweeps[idx].obLow            = 0;
   g_sweeps[idx].obStartTime      = 0;
   g_sweeps[idx].obEndTime        = 0;
   g_sweeps[idx].signalBar         = -1;
   g_sweeps[idx].signalTime        = 0;
}

//+------------------------------------------------------------------+
//| Classify sweep context: Range (fuel) vs HTF Extreme (caution)      |
//+------------------------------------------------------------------+
void ClassifySweepContext()
{
   for(int i = 0; i < g_sweepCount; i++)
   {
      bool isHTFExtreme = IsNearHTFExtreme(g_sweeps[i].levelPrice);
      bool isInRange    = IsWithinRange(g_sweeps[i].bar, g_sweeps[i].levelPrice);

      //--- HTF extreme takes priority
      if(isHTFExtreme)
         g_sweeps[i].context = CTX_HTF_EXTREME;
      else if(isInRange)
         g_sweeps[i].context = CTX_RANGE_SWEEP;
      else
         g_sweeps[i].context = CTX_UNKNOWN;
   }
}

//+------------------------------------------------------------------+
//| Check if sweep price is within a consolidation range               |
//+------------------------------------------------------------------+
bool IsWithinRange(int sweepBar, double sweepPrice)
{
   //--- Look for clustered swing highs AND lows within ~50 bars
   int lookback = 50;
   int rangeStart = sweepBar + lookback;
   int rangeEnd   = sweepBar;

   double localHigh = -999999;
   double localLow  = 999999;
   int    highCount = 0;
   int    lowCount  = 0;

   for(int i = 0; i < g_swingHighCount; i++)
   {
      if(g_swingHighs[i].bar >= rangeEnd && g_swingHighs[i].bar <= rangeStart)
      {
         if(g_swingHighs[i].price > localHigh) localHigh = g_swingHighs[i].price;
         highCount++;
      }
   }

   for(int i = 0; i < g_swingLowCount; i++)
   {
      if(g_swingLows[i].bar >= rangeEnd && g_swingLows[i].bar <= rangeStart)
      {
         if(g_swingLows[i].price < localLow) localLow = g_swingLows[i].price;
         lowCount++;
      }
   }

   //--- Need at least 2 highs and 2 lows in the area
   if(highCount < 2 || lowCount < 2) return false;

   //--- Check range width is reasonable (not trending strongly)
   double rangeWidth = localHigh - localLow;
   if(rangeWidth <= 0 || rangeWidth > g_atrValue * 4) return false;

   //--- Sweep price should be within or near the range boundaries
   if(sweepPrice >= localLow - g_atrValue * 0.5 &&
      sweepPrice <= localHigh + g_atrValue * 0.5)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Check if sweep price is near an HTF extreme (major swing H/L)      |
//+------------------------------------------------------------------+
bool IsNearHTFExtreme(double sweepPrice)
{
   double htfTol = g_atrValue * 0.5;

   for(int i = 0; i < g_htfSwingHighCount; i++)
   {
      if(MathAbs(sweepPrice - g_htfSwingHighs[i].price) <= htfTol)
         return true;
   }

   for(int i = 0; i < g_htfSwingLowCount; i++)
   {
      if(MathAbs(sweepPrice - g_htfSwingLows[i].price) <= htfTol)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Step 1: Check post-sweep structure (no CHoCH against trend)        |
//+------------------------------------------------------------------+
void CheckPostSweepStructure(int idx, const double &high[], const double &low[],
                              const double &close[], const datetime &time[],
                              int maxBar)
{
   int sweepBar = g_sweeps[idx].bar;
   int scanEnd  = MathMax(sweepBar - InpMaxBarsAfterSweep, 0);

   //--- Find the most recent swing high and swing low BEFORE the sweep
   double recentSwingLow  = 999999;
   double recentSwingHigh = 0;

   for(int i = 0; i < g_swingLowCount; i++)
   {
      if(g_swingLows[i].bar > sweepBar && g_swingLows[i].bar <= sweepBar + 30)
      {
         if(recentSwingLow > g_swingLows[i].price)
            recentSwingLow = g_swingLows[i].price;
      }
   }

   for(int i = 0; i < g_swingHighCount; i++)
   {
      if(g_swingHighs[i].bar > sweepBar && g_swingHighs[i].bar <= sweepBar + 30)
      {
         if(recentSwingHigh < g_swingHighs[i].price)
            recentSwingHigh = g_swingHighs[i].price;
      }
   }

   bool choch = false;

   if(g_sweeps[idx].direction == SWEEP_BULLISH)
   {
      //--- After bullish sweep (sweep below lows), check no candle CLOSES below recent swing low
      //--- That would be bearish CHoCH = structure broke against continuation
      if(recentSwingLow < 999999)
      {
         for(int b = sweepBar - 1; b >= scanEnd; b--)
         {
            if(close[b] < recentSwingLow)
            {
               choch = true;
               break;
            }
         }
      }
   }
   else
   {
      //--- After bearish sweep (sweep above highs), check no candle CLOSES above recent swing high
      if(recentSwingHigh > 0)
      {
         for(int b = sweepBar - 1; b >= scanEnd; b--)
         {
            if(close[b] > recentSwingHigh)
            {
               choch = true;
               break;
            }
         }
      }
   }

   g_sweeps[idx].chochOccurred = choch;

   if(choch)
      g_sweeps[idx].state = STATE_INVALIDATED;
   else
      g_sweeps[idx].state = STATE_STRUCTURE_HELD;
}

//+------------------------------------------------------------------+
//| Step 2: Detect displacement candle after sweep                     |
//+------------------------------------------------------------------+
void DetectDisplacement(int idx, const double &open[], const double &high[],
                        const double &low[], const double &close[],
                        const datetime &time[], int maxBar)
{
   int sweepBar = g_sweeps[idx].bar;
   int scanEnd  = MathMax(sweepBar - InpMaxBarsAfterSweep, 0);

   for(int b = sweepBar - 1; b >= scanEnd; b--)
   {
      double range = high[b] - low[b];
      if(range <= 0) continue;

      double body = MathAbs(close[b] - open[b]);
      double bodyRatio = body / range;

      if(bodyRatio < InpDisplacementRatio)
         continue;

      //--- Check direction matches sweep bias
      bool isBullCandle = (close[b] > open[b]);
      bool isBearCandle = (close[b] < open[b]);

      if(g_sweeps[idx].direction == SWEEP_BULLISH && !isBullCandle)
         continue;
      if(g_sweeps[idx].direction == SWEEP_BEARISH && !isBearCandle)
         continue;

      //--- Verify meaningful displacement (moved past the level)
      double threshold = g_atrValue * 0.3;

      if(g_sweeps[idx].direction == SWEEP_BULLISH && close[b] < g_sweeps[idx].levelPrice + threshold)
         continue;
      if(g_sweeps[idx].direction == SWEEP_BEARISH && close[b] > g_sweeps[idx].levelPrice - threshold)
         continue;

      //--- Found displacement
      g_sweeps[idx].displacementBar   = b;
      g_sweeps[idx].displacementTime  = time[b];
      g_sweeps[idx].displacementClose = close[b];
      g_sweeps[idx].state             = STATE_DISPLACED;
      return;
   }

   //--- No displacement found — state stays at STRUCTURE_HELD (not invalidated)
}

//+------------------------------------------------------------------+
//| Identify order block from displacement origin                      |
//+------------------------------------------------------------------+
void IdentifyOrderBlock(int idx, const double &open[], const double &high[],
                        const double &low[], const double &close[],
                        const datetime &time[], int maxBar)
{
   int dispBar = g_sweeps[idx].displacementBar;
   if(dispBar < 0) return;

   //--- Walk backward from displacement bar (up to 5 candles)
   //--- OB = first candle that is opposite color or small body
   int maxLookback = 5;

   for(int b = dispBar + 1; b <= MathMin(dispBar + maxLookback, maxBar); b++)
   {
      bool isBullCandle = (close[b] > open[b]);
      bool isBearCandle = (close[b] < open[b]);
      double body = MathAbs(close[b] - open[b]);
      double range = high[b] - low[b];
      bool isSmallBody = (range > 0 && body / range < 0.3);

      bool isOB = false;

      if(g_sweeps[idx].direction == SWEEP_BULLISH)
      {
         //--- For bullish continuation, OB = last bearish or small candle before bullish impulse
         if(isBearCandle || isSmallBody) isOB = true;
      }
      else
      {
         //--- For bearish continuation, OB = last bullish or small candle before bearish impulse
         if(isBullCandle || isSmallBody) isOB = true;
      }

      if(isOB)
      {
         g_sweeps[idx].obStartBar  = b;
         g_sweeps[idx].obEndBar    = MathMax(b - InpLevelBars, 0);
         g_sweeps[idx].obHigh      = high[b];
         g_sweeps[idx].obLow       = low[b];
         g_sweeps[idx].obStartTime = time[b];

         int endBarClamped = MathMax(b - InpLevelBars, 0);
         g_sweeps[idx].obEndTime = time[endBarClamped];
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Step 3: Check pullback respect of the OB zone                     |
//+------------------------------------------------------------------+
void CheckPullbackRespect(int idx, const double &high[], const double &low[],
                          const double &close[], const datetime &time[],
                          int maxBar)
{
   if(g_sweeps[idx].obStartBar < 0) return; // No OB identified

   int dispBar = g_sweeps[idx].displacementBar;
   int scanEnd = MathMax(dispBar - InpMaxBarsPullback, 0);

   double obHigh = g_sweeps[idx].obHigh;
   double obLow  = g_sweeps[idx].obLow;

   for(int b = dispBar - 1; b >= scanEnd; b--)
   {
      if(g_sweeps[idx].direction == SWEEP_BULLISH)
      {
         //--- Bullish: price pulls back INTO the demand zone (low touches OB)
         //--- and closes ABOVE the OB high (respected / held)
         if(low[b] <= obHigh && low[b] >= obLow && close[b] > obHigh)
         {
            g_sweeps[idx].signalBar  = b;
            g_sweeps[idx].signalTime = time[b];
            g_sweeps[idx].state      = STATE_ZONE_RESPECTED;
            return;
         }

         //--- If close goes BELOW OB low → zone broken → invalidated
         if(close[b] < obLow)
         {
            g_sweeps[idx].state = STATE_INVALIDATED;
            return;
         }
      }
      else
      {
         //--- Bearish: price pulls back INTO the supply zone (high touches OB)
         //--- and closes BELOW the OB low (respected / held)
         if(high[b] >= obLow && high[b] <= obHigh && close[b] < obLow)
         {
            g_sweeps[idx].signalBar  = b;
            g_sweeps[idx].signalTime = time[b];
            g_sweeps[idx].state      = STATE_ZONE_RESPECTED;
            return;
         }

         //--- If close goes ABOVE OB high → zone broken → invalidated
         if(close[b] > obHigh)
         {
            g_sweeps[idx].state = STATE_INVALIDATED;
            return;
         }
      }
   }

   //--- No pullback yet — stays at DISPLACED (still waiting)
}

//+------------------------------------------------------------------+
//| Draw all visual objects on chart                                    |
//+------------------------------------------------------------------+
void DrawAllObjects(const datetime &time[], const double &high[],
                    const double &low[])
{
   int totalBars = ArraySize(time);

   //--- Draw equal levels first (behind other elements)
   if(InpShowEqualHighs || InpShowEqualLows)
      DrawEqualLevels(time, totalBars);

   for(int i = 0; i < g_sweepCount; i++)
   {
      SweepEvent sw = g_sweeps[i];

      //--- Always draw sweep arrows
      if(InpShowSweepArrows)
         DrawSweepArrow(i, time, high, low, totalBars);

      //--- Context label
      if(InpShowContextLabels && sw.context != CTX_UNKNOWN)
         DrawContextLabel(i, time, high, low, totalBars);

      //--- Displacement marker
      if(InpShowDisplacement && sw.state >= STATE_DISPLACED && sw.state != STATE_INVALIDATED)
         DrawDisplacementMarker(i, time, high, low, totalBars);

      //--- Order block zone
      if(InpShowZones && sw.obStartBar >= 0 && sw.state >= STATE_DISPLACED && sw.state != STATE_INVALIDATED)
         DrawOrderBlockZone(i, time, totalBars);

      //--- Signal arrow
      if(InpShowSignals && sw.state == STATE_ZONE_RESPECTED)
         DrawSignal(i, time, high, low, totalBars);
   }

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw equal highs and lows (liquidity levels)                       |
//+------------------------------------------------------------------+
void DrawEqualLevels(const datetime &time[], int totalBars)
{
   for(int i = 0; i < g_equalLevelCount; i++)
   {
      EqualLevel eq = g_equalLevels[i];

      //--- Skip if toggle is off for this type
      if(eq.isHigh && !InpShowEqualHighs) continue;
      if(!eq.isHigh && !InpShowEqualLows) continue;

      //--- Skip swept levels (hide them)
      if(eq.swept) continue;

      //--- Determine colors and style
      color lineColor = eq.isHigh ? InpEqualHighColor : InpEqualLowColor;
      ENUM_LINE_STYLE lineStyle = STYLE_SOLID;
      int lineWidth = InpEqualLineWidth;

      //--- Calculate line endpoints
      int lineStartBar = eq.startBar;
      int lineEndBar = 0; // Extend to current bar

      //--- Clamp to bounds
      if(lineStartBar >= totalBars) lineStartBar = totalBars - 1;
      if(lineEndBar >= totalBars)   lineEndBar = totalBars - 1;
      if(lineStartBar < 0) lineStartBar = 0;
      if(lineEndBar < 0)   lineEndBar = 0;

      //--- Draw the level line
      string lineName = g_objPrefix + "EQ_" + IntegerToString(i);
      DrawHorizontalLine(lineName, time[lineStartBar], time[lineEndBar],
                        eq.price, lineColor, lineWidth, lineStyle);

      //--- Draw label
      string labelText;
      if(eq.isHigh)
         labelText = "EQH x" + IntegerToString(eq.touches);
      else
         labelText = "EQL x" + IntegerToString(eq.touches);

      string labelName = g_objPrefix + "EQL_" + IntegerToString(i);
      DrawLabel(labelName, time[lineStartBar], eq.price,
                labelText, lineColor, eq.isHigh, InpFontSize);
   }
}

//+------------------------------------------------------------------+
//| Draw sweep arrow                                                   |
//+------------------------------------------------------------------+
void DrawSweepArrow(int idx, const datetime &time[], const double &high[],
                    const double &low[], int totalBars)
{
   SweepEvent sw = g_sweeps[idx];
   if(sw.bar < 0 || sw.bar >= totalBars) return;

   bool isBearish = (sw.direction == SWEEP_BEARISH);
   int arrowCode = isBearish ? 234 : 233; // Down for bear sweep (above), Up for bull sweep (below)

   string name = g_objPrefix + "SA_" + IntegerToString(idx);

   if(!ObjectCreate(0, name, OBJ_ARROW, 0, sw.time, sw.sweepPrice))
      ObjectMove(0, name, 0, sw.time, sw.sweepPrice);

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpSweepArrowColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isBearish ? ANCHOR_BOTTOM : ANCHOR_TOP);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Draw context label (RANGE SWEEP / HTF EXTREME)                     |
//+------------------------------------------------------------------+
void DrawContextLabel(int idx, const datetime &time[], const double &high[],
                      const double &low[], int totalBars)
{
   SweepEvent sw = g_sweeps[idx];
   if(sw.bar < 0 || sw.bar >= totalBars) return;

   string text;
   color  clr;

   if(sw.context == CTX_RANGE_SWEEP)
   {
      text = "RANGE - Fuel";
      clr  = InpContextFuelColor;
   }
   else
   {
      text = "HTF EXTREME - Caution";
      clr  = InpContextCautionColor;
   }

   bool above = (sw.direction == SWEEP_BEARISH);
   double price = sw.sweepPrice;

   string name = g_objPrefix + "CX_" + IntegerToString(idx);
   DrawLabel(name, sw.time, price, text, clr, above, InpFontSize - 1);
}

//+------------------------------------------------------------------+
//| Draw displacement marker                                           |
//+------------------------------------------------------------------+
void DrawDisplacementMarker(int idx, const datetime &time[], const double &high[],
                            const double &low[], int totalBars)
{
   SweepEvent sw = g_sweeps[idx];
   if(sw.displacementBar < 0 || sw.displacementBar >= totalBars) return;

   bool isBull = (sw.direction == SWEEP_BULLISH);
   int arrowCode = isBull ? 233 : 234;
   color clr = isBull ? InpDisplaceBullColor : InpDisplaceBearColor;

   double price = isBull ? high[sw.displacementBar] : low[sw.displacementBar];

   string name = g_objPrefix + "DP_" + IntegerToString(idx);

   if(!ObjectCreate(0, name, OBJ_ARROW, 0, sw.displacementTime, price))
      ObjectMove(0, name, 0, sw.displacementTime, price);

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isBull ? ANCHOR_BOTTOM : ANCHOR_TOP);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   //--- Label
   string labelName = g_objPrefix + "DPL_" + IntegerToString(idx);
   DrawLabel(labelName, sw.displacementTime, price,
             "DISP", clr, isBull, InpFontSize - 1);
}

//+------------------------------------------------------------------+
//| Draw order block zone as rectangle                                 |
//+------------------------------------------------------------------+
void DrawOrderBlockZone(int idx, const datetime &time[], int totalBars)
{
   SweepEvent sw = g_sweeps[idx];
   if(sw.obStartBar < 0 || sw.obStartBar >= totalBars) return;

   int endBar = sw.obEndBar;
   if(endBar >= totalBars) endBar = totalBars - 1;
   if(endBar < 0) endBar = 0;

   bool isBull = (sw.direction == SWEEP_BULLISH);
   color clr = isBull ? InpDemandZoneColor : InpSupplyZoneColor;

   string rectName = g_objPrefix + "OB_" + IntegerToString(idx);

   if(ObjectCreate(0, rectName, OBJ_RECTANGLE, 0,
                    time[sw.obStartBar], sw.obHigh,
                    time[endBar], sw.obLow))
   {
      ObjectSetInteger(0, rectName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, rectName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
      ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
      ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, rectName, OBJPROP_HIDDEN, true);
   }

   //--- OB label
   string labelName = g_objPrefix + "OBL_" + IntegerToString(idx);
   string labelText = isBull ? "Demand OB" : "Supply OB";
   double labelPrice = isBull ? sw.obLow : sw.obHigh;
   DrawLabel(labelName, time[sw.obStartBar], labelPrice,
             labelText, clr, !isBull, InpFontSize - 1);
}

//+------------------------------------------------------------------+
//| Draw signal arrow and text                                         |
//+------------------------------------------------------------------+
void DrawSignal(int idx, const datetime &time[], const double &high[],
                const double &low[], int totalBars)
{
   SweepEvent sw = g_sweeps[idx];
   if(sw.signalBar < 0 || sw.signalBar >= totalBars) return;

   bool isBull = (sw.direction == SWEEP_BULLISH);
   color clr = isBull ? InpSignalBullColor : InpSignalBearColor;
   int arrowCode = isBull ? 233 : 234;

   double price = isBull ? low[sw.signalBar] : high[sw.signalBar];

   //--- Large signal arrow
   string arrowName = g_objPrefix + "SIG_" + IntegerToString(idx);

   if(!ObjectCreate(0, arrowName, OBJ_ARROW, 0, sw.signalTime, price))
      ObjectMove(0, arrowName, 0, sw.signalTime, price);

   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR, isBull ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, true);

   //--- Signal text label
   string labelName = g_objPrefix + "SIGL_" + IntegerToString(idx);
   string labelText = "CONTINUATION";
   DrawLabel(labelName, sw.signalTime, price, labelText, clr, !isBull, InpFontSize);
}

//+------------------------------------------------------------------+
//| Build dashboard via Comment()                                      |
//+------------------------------------------------------------------+
void BuildDashboard()
{
   string dash = "";
   string sep = "------------------------------------------------------------\n";

   dash += sep;
   dash += " SmartMoneyContinuation v1.0 | " + _Symbol + " " + GetTimeframeString() + "\n";
   dash += sep;

   //--- Count signals
   int signalCount = 0;
   for(int i = 0; i < g_sweepCount; i++)
   {
      if(g_sweeps[i].state == STATE_ZONE_RESPECTED)
         signalCount++;
   }

   dash += " ATR(" + IntegerToString(InpATRPeriod) + "): " + DoubleToString(g_atrValue, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS))
         + " | Sweeps: " + IntegerToString(g_sweepCount)
         + " | Signals: " + IntegerToString(signalCount) + "\n\n";

   //--- Show details for recent sweeps (last 10 max)
   int showCount = MathMin(g_sweepCount, 10);
   int startIdx  = g_sweepCount - showCount;

   for(int i = startIdx; i < g_sweepCount; i++)
   {
      SweepEvent sw = g_sweeps[i];
      int num = i - startIdx + 1;

      string dirStr = (sw.direction == SWEEP_BULLISH) ? "BULLISH" : "BEARISH";
      string ctxStr = "";

      if(sw.context == CTX_RANGE_SWEEP)
         ctxStr = " [RANGE SWEEP - Fuel]";
      else if(sw.context == CTX_HTF_EXTREME)
         ctxStr = " [HTF EXTREME - Caution]";

      dash += " #" + IntegerToString(num) + " " + dirStr + " sweep @ "
            + DoubleToString(sw.levelPrice, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS))
            + ctxStr + "\n";

      //--- Step 1: Structure
      if(sw.state == STATE_INVALIDATED && sw.chochOccurred)
      {
         dash += "    [X] Structure BROKE (CHoCH) - INVALIDATED\n";
         dash += "\n";
         continue;
      }
      else if(sw.state >= STATE_STRUCTURE_HELD)
      {
         dash += "    [X] Structure held\n";
      }
      else
      {
         dash += "    [ ] Checking structure...\n";
         dash += "\n";
         continue;
      }

      //--- Step 2: Displacement
      if(sw.state >= STATE_DISPLACED)
      {
         dash += "    [X] Displacement confirmed\n";
      }
      else if(sw.state == STATE_INVALIDATED)
      {
         dash += "    [ ] No displacement found\n";
         dash += "\n";
         continue;
      }
      else
      {
         dash += "    [ ] No displacement found\n";
         dash += "\n";
         continue;
      }

      //--- Step 3: Pullback
      if(sw.state == STATE_ZONE_RESPECTED)
      {
         dash += "    [X] Pullback respected -> CONTINUATION SIGNAL\n";
      }
      else if(sw.state == STATE_INVALIDATED)
      {
         dash += "    [X] Zone broken - INVALIDATED\n";
      }
      else
      {
         dash += "    [ ] Waiting for pullback...\n";
      }

      dash += "\n";
   }

   dash += sep;

   Comment(dash);
}

//+------------------------------------------------------------------+
//| Get timeframe as string                                            |
//+------------------------------------------------------------------+
string GetTimeframeString()
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();

   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "TF" + IntegerToString(PeriodSeconds() / 60);
   }
}

//+------------------------------------------------------------------+
//| Helper: Draw a text label on the chart                             |
//+------------------------------------------------------------------+
void DrawLabel(string name, datetime labelTime, double price,
               string text, color clr, bool above, int fontSize)
{
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, labelTime, price))
      ObjectMove(0, name, 0, labelTime, price);

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
   g_swingHighCount    = 0;
   g_swingLowCount     = 0;
   g_htfSwingHighCount = 0;
   g_htfSwingLowCount  = 0;
   g_sweepCount        = 0;
   g_equalLevelCount   = 0;

   ArrayResize(g_swingHighs, 0);
   ArrayResize(g_swingLows, 0);
   ArrayResize(g_htfSwingHighs, 0);
   ArrayResize(g_htfSwingLows, 0);
   ArrayResize(g_sweeps, 0);
   ArrayResize(g_equalLevels, 0);
}
//+------------------------------------------------------------------+
