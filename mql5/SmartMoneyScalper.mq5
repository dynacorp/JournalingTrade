//+------------------------------------------------------------------+
//|                                          SmartMoneyScalper.mq5   |
//|                TradeMind Smart Money Scalping Indicator            |
//|  Scalping indicator using the Sweep->Hold->Continue model.       |
//|  Draws entry zones, SL/TP levels, and fires alerts on signals.   |
//|  Designed for M1/M5 day trading.                                 |
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
   SWEEP_BULLISH = 0,   // Bullish (sweep below lows -> expect move up)
   SWEEP_BEARISH,        // Bearish (sweep above highs -> expect move down)
};

enum ENUM_SWEEP_CONTEXT
{
   CTX_RANGE_SWEEP = 0, // Range sweep - fuel for continuation
   CTX_HTF_EXTREME,      // HTF extreme sweep - reversal caution
   CTX_UNKNOWN,          // Context not classified
};

enum ENUM_SIGNAL_STATE
{
   STATE_SWEEP_DETECTED = 0,  // Sweep found, checking conditions
   STATE_STRUCTURE_HELD,       // Step 1 passed: no CHoCH against trend
   STATE_DISPLACED,            // Step 2 passed: displacement candle found
   STATE_ZONE_RESPECTED,       // Step 3 passed: pullback respected OB -> SIGNAL
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
   int            bar;
   datetime       time;
   double         levelPrice;
   double         sweepPrice;
   ENUM_SWEEP_DIR direction;
   ENUM_SWEEP_CONTEXT context;
   ENUM_SIGNAL_STATE  state;

   //--- Step 1: Structure
   bool           chochOccurred;

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

//+------------------------------------------------------------------+
//| Input Parameters - Detection                                       |
//+------------------------------------------------------------------+
input group "=== Detection Settings ==="
input int      InpSwingStrength      = 5;              // Swing strength (bars each side)
input int      InpHTFSwingStrength   = 10;             // HTF extreme swing strength (larger)
input int      InpMaxBars            = 300;            // Max bars to analyze
input double   InpDisplacementRatio  = 0.7;            // Min body/range for displacement candle
input int      InpATRPeriod          = 14;             // ATR period
input double   InpEqualTolerance     = 0.3;            // Equal level tolerance (x ATR)
input int      InpMaxBarsAfterSweep  = 20;             // Window to find displacement after sweep
input int      InpMaxBarsPullback    = 30;             // Window to find pullback after displacement

//+------------------------------------------------------------------+
//| Input Parameters - Signal Levels                                   |
//+------------------------------------------------------------------+
input group "=== Signal Levels ==="
input double   InpRiskReward         = 2.0;            // Risk:Reward ratio for TP line
input double   InpSLBufferATR        = 0.1;            // SL buffer beyond OB (x ATR)
input int      InpLevelBars          = 20;             // SL/TP line forward extension (bars)

//+------------------------------------------------------------------+
//| Input Parameters - Alerts                                          |
//+------------------------------------------------------------------+
input group "=== Alerts ==="
input bool     InpAlertPopup         = true;           // Alert: Popup dialog
input bool     InpAlertSound         = true;           // Alert: Play sound
input bool     InpAlertPush          = false;          // Alert: Push notification (mobile)

//+------------------------------------------------------------------+
//| Input Parameters - Visual                                          |
//+------------------------------------------------------------------+
input group "=== Visual Settings ==="
input bool     InpShowSweepArrows    = true;           // Show sweep arrows
input bool     InpShowDisplacement   = true;           // Show displacement markers
input bool     InpShowZones          = true;           // Show order block zones
input bool     InpShowSignals        = true;           // Show signal arrows
input bool     InpShowSLTP           = true;           // Show SL/TP levels on signals
input bool     InpShowContextLabels  = true;           // Show context labels (Fuel / Caution)
input bool     InpShowDashboard      = true;           // Show dashboard
input color    InpSweepArrowColor    = clrGold;        // Sweep arrow color
input color    InpDisplaceBullColor  = clrLime;        // Bullish displacement color
input color    InpDisplaceBearColor  = clrRed;         // Bearish displacement color
input color    InpDemandZoneColor    = clrDodgerBlue;  // Demand zone color
input color    InpSupplyZoneColor    = clrCrimson;     // Supply zone color
input color    InpSignalBullColor    = clrLime;        // Bull signal color
input color    InpSignalBearColor    = clrRed;         // Bear signal color
input color    InpContextFuelColor   = clrGold;        // Context: fuel label color
input color    InpContextCautionColor = clrOrangeRed;  // Context: caution label color
input color    InpSLColor            = clrRed;         // SL line color
input color    InpTPColor            = clrLime;        // TP line color
input int      InpFontSize           = 8;              // Label font size

//+------------------------------------------------------------------+
//| Global Variables                                                   |
//+------------------------------------------------------------------+
//--- Detection arrays
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

double           g_atrValue = 0;

//--- Alert tracking
datetime         g_lastAlertTime = 0;
int              g_lastCalculatedBars = 0;

//--- Visual
string           g_objPrefix = "SMS_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                           |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("SmartMoneyScalper v1.0 initializing...");
   Print("Swing: ", InpSwingStrength, " | HTF: ", InpHTFSwingStrength,
         " | Displacement: ", DoubleToString(InpDisplacementRatio, 1),
         " | RR: 1:", DoubleToString(InpRiskReward, 1));

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
   Print("SmartMoneyScalper deinitialized");
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

   //--- 4. Detect sweeps
   DetectSweeps(high, low, close, time, startBar);

   //--- 5. Classify sweep context
   ClassifySweepContext();

   //--- 6. Run 3-step model for each sweep
   for(int i = 0; i < g_sweepCount; i++)
   {
      if(g_sweeps[i].state == STATE_INVALIDATED)
         continue;

      CheckPostSweepStructure(i, high, low, close, time, startBar);
      if(g_sweeps[i].state == STATE_INVALIDATED)
         continue;

      DetectDisplacement(i, open, high, low, close, time, startBar);
      if(g_sweeps[i].state < STATE_DISPLACED)
         continue;

      IdentifyOrderBlock(i, open, high, low, close, time, startBar);
      CheckPullbackRespect(i, high, low, close, time, startBar);
   }

   //--- 7. Draw everything
   DrawAllObjects(time, high, low);

   //--- 8. Check for fresh signal alerts
   CheckAlerts(time);

   //--- 9. Dashboard
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
//| Detect swing highs and lows                                        |
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
//| Detect sweeps: price wicking through swing/equal levels            |
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
   int    eqHighBars[];
   int    eqHighCount = 0;

   ClusterSwingLevels(g_swingHighs, g_swingHighCount, tolerance,
                      eqHighPrices, eqHighBars, eqHighCount);

   //--- Cluster swing lows into equal-low levels
   double eqLowPrices[];
   int    eqLowBars[];
   int    eqLowCount = 0;

   ClusterSwingLevels(g_swingLows, g_swingLowCount, tolerance,
                      eqLowPrices, eqLowBars, eqLowCount);

   //--- Add standalone swings
   AddStandaloneSwings(g_swingHighs, g_swingHighCount, eqHighPrices, eqHighBars, eqHighCount, tolerance);
   AddStandaloneSwings(g_swingLows, g_swingLowCount, eqLowPrices, eqLowBars, eqLowCount, tolerance);

   //--- Scan for sweeps of equal highs (bearish sweep)
   for(int i = 0; i < eqHighCount; i++)
   {
      int scanStart = eqHighBars[i] - 1;
      if(scanStart < 0) scanStart = 0;

      for(int b = scanStart; b >= 0; b--)
      {
         if(high[b] > eqHighPrices[i] + sweepTol && close[b] < eqHighPrices[i])
         {
            if(!IsDuplicateSweep(b, eqHighPrices[i], dedupPrice))
               AddSweep(b, time[b], eqHighPrices[i], high[b], SWEEP_BEARISH);
            break;
         }
      }
   }

   //--- Scan for sweeps of equal lows (bullish sweep)
   for(int i = 0; i < eqLowCount; i++)
   {
      int scanStart = eqLowBars[i] - 1;
      if(scanStart < 0) scanStart = 0;

      for(int b = scanStart; b >= 0; b--)
      {
         if(low[b] < eqLowPrices[i] - sweepTol && close[b] > eqLowPrices[i])
         {
            if(!IsDuplicateSweep(b, eqLowPrices[i], dedupPrice))
               AddSweep(b, time[b], eqLowPrices[i], low[b], SWEEP_BULLISH);
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cluster swing points at similar prices                             |
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
      int    newestBar = swings[i].bar;
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
//| Add standalone swings as sweep-able levels                         |
//+------------------------------------------------------------------+
void AddStandaloneSwings(const SwingPoint &swings[], int count,
                         double &prices[], int &bars[], int &outCount,
                         double tolerance)
{
   for(int i = 0; i < count; i++)
   {
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
//| Check for duplicate sweep                                          |
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
//| Add a sweep event                                                  |
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
//| Classify sweep context                                             |
//+------------------------------------------------------------------+
void ClassifySweepContext()
{
   for(int i = 0; i < g_sweepCount; i++)
   {
      bool isHTFExtreme = IsNearHTFExtreme(g_sweeps[i].levelPrice);
      bool isInRange    = IsWithinRange(g_sweeps[i].bar, g_sweeps[i].levelPrice);

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

   if(highCount < 2 || lowCount < 2) return false;

   double rangeWidth = localHigh - localLow;
   if(rangeWidth <= 0 || rangeWidth > g_atrValue * 4) return false;

   if(sweepPrice >= localLow - g_atrValue * 0.5 &&
      sweepPrice <= localHigh + g_atrValue * 0.5)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Check if sweep is near an HTF extreme                              |
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
//| Step 1: Check post-sweep structure                                 |
//+------------------------------------------------------------------+
void CheckPostSweepStructure(int idx, const double &high[], const double &low[],
                              const double &close[], const datetime &time[],
                              int maxBar)
{
   int sweepBar = g_sweeps[idx].bar;
   int scanEnd  = MathMax(sweepBar - InpMaxBarsAfterSweep, 0);

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
//| Step 2: Detect displacement candle                                 |
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

      bool isBullCandle = (close[b] > open[b]);
      bool isBearCandle = (close[b] < open[b]);

      if(g_sweeps[idx].direction == SWEEP_BULLISH && !isBullCandle)
         continue;
      if(g_sweeps[idx].direction == SWEEP_BEARISH && !isBearCandle)
         continue;

      double threshold = g_atrValue * 0.3;

      if(g_sweeps[idx].direction == SWEEP_BULLISH && close[b] < g_sweeps[idx].levelPrice + threshold)
         continue;
      if(g_sweeps[idx].direction == SWEEP_BEARISH && close[b] > g_sweeps[idx].levelPrice - threshold)
         continue;

      g_sweeps[idx].displacementBar   = b;
      g_sweeps[idx].displacementTime  = time[b];
      g_sweeps[idx].displacementClose = close[b];
      g_sweeps[idx].state             = STATE_DISPLACED;
      return;
   }
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
         if(isBearCandle || isSmallBody) isOB = true;
      }
      else
      {
         if(isBullCandle || isSmallBody) isOB = true;
      }

      if(isOB)
      {
         g_sweeps[idx].obStartBar  = b;
         g_sweeps[idx].obEndBar    = MathMax(b - InpMaxBarsPullback, 0);
         g_sweeps[idx].obHigh      = high[b];
         g_sweeps[idx].obLow       = low[b];
         g_sweeps[idx].obStartTime = time[b];

         int endBarClamped = MathMax(b - InpMaxBarsPullback, 0);
         g_sweeps[idx].obEndTime = time[endBarClamped];
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Step 3: Check pullback respect of OB zone                         |
//+------------------------------------------------------------------+
void CheckPullbackRespect(int idx, const double &high[], const double &low[],
                          const double &close[], const datetime &time[],
                          int maxBar)
{
   if(g_sweeps[idx].obStartBar < 0) return;

   int dispBar = g_sweeps[idx].displacementBar;
   int scanEnd = MathMax(dispBar - InpMaxBarsPullback, 0);

   double obHigh = g_sweeps[idx].obHigh;
   double obLow  = g_sweeps[idx].obLow;

   for(int b = dispBar - 1; b >= scanEnd; b--)
   {
      if(g_sweeps[idx].direction == SWEEP_BULLISH)
      {
         if(low[b] <= obHigh && low[b] >= obLow && close[b] > obHigh)
         {
            g_sweeps[idx].signalBar  = b;
            g_sweeps[idx].signalTime = time[b];
            g_sweeps[idx].state      = STATE_ZONE_RESPECTED;
            return;
         }

         if(close[b] < obLow)
         {
            g_sweeps[idx].state = STATE_INVALIDATED;
            return;
         }
      }
      else
      {
         if(high[b] >= obLow && high[b] <= obHigh && close[b] < obLow)
         {
            g_sweeps[idx].signalBar  = b;
            g_sweeps[idx].signalTime = time[b];
            g_sweeps[idx].state      = STATE_ZONE_RESPECTED;
            return;
         }

         if(close[b] > obHigh)
         {
            g_sweeps[idx].state = STATE_INVALIDATED;
            return;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for new signals and fire alerts                              |
//+------------------------------------------------------------------+
void CheckAlerts(const datetime &time[])
{
   if(!InpAlertPopup && !InpAlertSound && !InpAlertPush)
      return;

   for(int i = 0; i < g_sweepCount; i++)
   {
      SweepEvent sw = g_sweeps[i];

      //--- Only alert on completed signals
      if(sw.state != STATE_ZONE_RESPECTED) continue;

      //--- Only alert on fresh signals (bar 1 or 2)
      if(sw.signalBar > 2) continue;

      //--- Only alert once per signal
      if(sw.signalTime <= g_lastAlertTime) continue;

      //--- Build alert message
      string dir = (sw.direction == SWEEP_BULLISH) ? "BUY" : "SELL";
      string ctx = "";
      if(sw.context == CTX_RANGE_SWEEP)
         ctx = " [Fuel]";
      else if(sw.context == CTX_HTF_EXTREME)
         ctx = " [HTF Caution]";

      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

      //--- Calculate SL/TP for alert
      double slBuffer = g_atrValue * InpSLBufferATR;
      double entry, sl, tp;

      if(sw.direction == SWEEP_BULLISH)
      {
         entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         sl = sw.obLow - slBuffer;
         tp = entry + MathAbs(entry - sl) * InpRiskReward;
      }
      else
      {
         entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         sl = sw.obHigh + slBuffer;
         tp = entry - MathAbs(entry - sl) * InpRiskReward;
      }

      string msg = "SmartMoneyScalper | " + _Symbol + " " + GetTimeframeString()
                 + " | " + dir + " SIGNAL" + ctx
                 + " | Entry: " + DoubleToString(entry, digits)
                 + " | SL: " + DoubleToString(sl, digits)
                 + " | TP: " + DoubleToString(tp, digits);

      if(InpAlertPopup)
         Alert(msg);

      if(InpAlertSound)
         PlaySound("alert2.wav");

      if(InpAlertPush)
         SendNotification(msg);

      g_lastAlertTime = sw.signalTime;
   }
}

//+------------------------------------------------------------------+
//| Draw all visual objects on chart                                    |
//+------------------------------------------------------------------+
void DrawAllObjects(const datetime &time[], const double &high[],
                    const double &low[])
{
   int totalBars = ArraySize(time);

   for(int i = 0; i < g_sweepCount; i++)
   {
      SweepEvent sw = g_sweeps[i];

      //--- Sweep arrows
      if(InpShowSweepArrows)
         DrawSweepArrow(i, time, high, low, totalBars);

      //--- Context labels
      if(InpShowContextLabels && sw.context != CTX_UNKNOWN)
         DrawContextLabel(i, time, high, low, totalBars);

      //--- Displacement markers
      if(InpShowDisplacement && sw.state >= STATE_DISPLACED && sw.state != STATE_INVALIDATED)
         DrawDisplacementMarker(i, time, high, low, totalBars);

      //--- Order block zones
      if(InpShowZones && sw.obStartBar >= 0 && sw.state >= STATE_DISPLACED && sw.state != STATE_INVALIDATED)
         DrawOrderBlockZone(i, time, totalBars);

      //--- Signal arrows + SL/TP levels
      if(InpShowSignals && sw.state == STATE_ZONE_RESPECTED)
      {
         DrawSignal(i, time, high, low, totalBars);

         if(InpShowSLTP)
            DrawSLTPLevels(i, time, totalBars);
      }
   }

   ChartRedraw(0);
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
   int arrowCode = isBearish ? 234 : 233;

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
//| Draw context label (RANGE / HTF EXTREME)                           |
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

   string name = g_objPrefix + "CX_" + IntegerToString(idx);
   DrawLabel(name, sw.time, sw.sweepPrice, text, clr, above, InpFontSize - 1);
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
   DrawLabel(labelName, sw.displacementTime, price, "DISP", clr, isBull, InpFontSize - 1);
}

//+------------------------------------------------------------------+
//| Draw order block zone                                              |
//+------------------------------------------------------------------+
void DrawOrderBlockZone(int idx, const datetime &time[], int totalBars)
{
   SweepEvent sw = g_sweeps[idx];
   if(sw.obStartBar < 0 || sw.obStartBar >= totalBars) return;

   int endBar = MathMax(sw.obEndBar, 0);
   if(endBar >= totalBars) endBar = totalBars - 1;

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
   DrawLabel(labelName, time[sw.obStartBar], labelPrice, labelText, clr, !isBull, InpFontSize - 1);
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

   //--- Signal text
   string labelText = isBull ? "BUY SIGNAL" : "SELL SIGNAL";
   string labelName = g_objPrefix + "SIGL_" + IntegerToString(idx);
   DrawLabel(labelName, sw.signalTime, price, labelText, clr, !isBull, InpFontSize);
}

//+------------------------------------------------------------------+
//| Draw SL and TP levels for a completed signal                       |
//+------------------------------------------------------------------+
void DrawSLTPLevels(int idx, const datetime &time[], int totalBars)
{
   SweepEvent sw = g_sweeps[idx];
   if(sw.signalBar < 0 || sw.signalBar >= totalBars) return;
   if(sw.obStartBar < 0) return;

   bool isBull = (sw.direction == SWEEP_BULLISH);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double slBuffer = g_atrValue * InpSLBufferATR;

   //--- Calculate SL from OB zone + buffer
   double sl;
   if(isBull)
      sl = sw.obLow - slBuffer;
   else
      sl = sw.obHigh + slBuffer;

   //--- Entry is approximate (OB edge where pullback respects)
   double entry;
   if(isBull)
      entry = sw.obHigh;   // Entry at top of demand zone
   else
      entry = sw.obLow;    // Entry at bottom of supply zone

   //--- Calculate TP from RR ratio
   double slDist = MathAbs(entry - sl);
   double tp;
   if(isBull)
      tp = entry + slDist * InpRiskReward;
   else
      tp = entry - slDist * InpRiskReward;

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   //--- Line time range: from signal bar forward by InpLevelBars
   int lineEndBar = MathMax(sw.signalBar - InpLevelBars, 0);
   if(lineEndBar >= totalBars) lineEndBar = totalBars - 1;

   datetime lineStart = sw.signalTime;
   datetime lineEnd   = time[lineEndBar];

   //--- Draw SL line
   string slName = g_objPrefix + "SL_" + IntegerToString(idx);
   DrawHorizontalLine(slName, lineStart, lineEnd, sl, InpSLColor, 2, STYLE_DASH);

   //--- SL label
   string slLabel = g_objPrefix + "SLL_" + IntegerToString(idx);
   string slText = "SL " + DoubleToString(sl, digits);
   DrawLabel(slLabel, lineStart, sl, slText, InpSLColor, !isBull, InpFontSize - 1);

   //--- Draw TP line
   string tpName = g_objPrefix + "TP_" + IntegerToString(idx);
   DrawHorizontalLine(tpName, lineStart, lineEnd, tp, InpTPColor, 2, STYLE_DASH);

   //--- TP label with RR
   string tpLabel = g_objPrefix + "TPL_" + IntegerToString(idx);
   string tpText = "TP " + DoubleToString(tp, digits) + " (1:" + DoubleToString(InpRiskReward, 1) + ")";
   DrawLabel(tpLabel, lineStart, tp, tpText, InpTPColor, isBull, InpFontSize - 1);
}

//+------------------------------------------------------------------+
//| Build dashboard via Comment()                                      |
//+------------------------------------------------------------------+
void BuildDashboard()
{
   string dash = "";
   string sep = "------------------------------------------------------------\n";

   dash += sep;
   dash += " SmartMoneyScalper v1.0 | " + _Symbol + " " + GetTimeframeString() + "\n";
   dash += sep;

   //--- Status
   dash += " ATR(" + IntegerToString(InpATRPeriod) + "): "
         + DoubleToString(g_atrValue, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS))
         + " | RR: 1:" + DoubleToString(InpRiskReward, 1)
         + " | Spread: " + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)) + " pts\n";

   //--- Signal counts
   int signalCount = 0;
   int activeCount = 0;
   for(int i = 0; i < g_sweepCount; i++)
   {
      if(g_sweeps[i].state == STATE_ZONE_RESPECTED) signalCount++;
      if(g_sweeps[i].state != STATE_INVALIDATED) activeCount++;
   }

   dash += " Sweeps: " + IntegerToString(g_sweepCount)
         + " | Active: " + IntegerToString(activeCount)
         + " | Signals: " + IntegerToString(signalCount) + "\n\n";

   //--- Recent sweep details (last 8)
   int showCount = MathMin(g_sweepCount, 8);
   int startIdx  = g_sweepCount - showCount;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = startIdx; i < g_sweepCount; i++)
   {
      SweepEvent sw = g_sweeps[i];
      int num = i - startIdx + 1;

      string dirStr = (sw.direction == SWEEP_BULLISH) ? "BULL" : "BEAR";
      string ctxStr = "";

      if(sw.context == CTX_RANGE_SWEEP)
         ctxStr = " [Fuel]";
      else if(sw.context == CTX_HTF_EXTREME)
         ctxStr = " [HTFx]";

      dash += " #" + IntegerToString(num) + " " + dirStr + " @ "
            + DoubleToString(sw.levelPrice, digits)
            + ctxStr + "\n";

      //--- Step 1
      if(sw.state == STATE_INVALIDATED && sw.chochOccurred)
      {
         dash += "   [X] CHoCH - INVALID\n\n";
         continue;
      }
      else if(sw.state >= STATE_STRUCTURE_HELD)
         dash += "   [v] Structure held\n";
      else
      {
         dash += "   [ ] Checking...\n\n";
         continue;
      }

      //--- Step 2
      if(sw.state >= STATE_DISPLACED)
         dash += "   [v] Displacement\n";
      else
      {
         dash += "   [ ] No displacement\n\n";
         continue;
      }

      //--- Step 3
      if(sw.state == STATE_ZONE_RESPECTED)
      {
         string dir = (sw.direction == SWEEP_BULLISH) ? "BUY" : "SELL";
         dash += "   [v] OB respected -> " + dir + " SIGNAL\n";

         //--- Show SL/TP levels
         if(sw.obStartBar >= 0)
         {
            double slBuffer = g_atrValue * InpSLBufferATR;
            double sl, entry, tp;

            if(sw.direction == SWEEP_BULLISH)
            {
               sl = sw.obLow - slBuffer;
               entry = sw.obHigh;
            }
            else
            {
               sl = sw.obHigh + slBuffer;
               entry = sw.obLow;
            }

            double slDist = MathAbs(entry - sl);
            if(sw.direction == SWEEP_BULLISH)
               tp = entry + slDist * InpRiskReward;
            else
               tp = entry - slDist * InpRiskReward;

            dash += "       Entry: ~" + DoubleToString(entry, digits)
                  + " | SL: " + DoubleToString(sl, digits)
                  + " | TP: " + DoubleToString(tp, digits) + "\n";
         }
      }
      else if(sw.state == STATE_INVALIDATED)
         dash += "   [X] Zone broken\n";
      else
         dash += "   [ ] Waiting pullback...\n";

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
//| Helper: Draw a horizontal line segment                             |
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
//| Clean all indicator objects from chart                              |
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
//| Reset all detection arrays                                         |
//+------------------------------------------------------------------+
void ResetArrays()
{
   g_swingHighCount    = 0;
   g_swingLowCount     = 0;
   g_htfSwingHighCount = 0;
   g_htfSwingLowCount  = 0;
   g_sweepCount        = 0;

   ArrayResize(g_swingHighs, 0);
   ArrayResize(g_swingLows, 0);
   ArrayResize(g_htfSwingHighs, 0);
   ArrayResize(g_htfSwingLows, 0);
   ArrayResize(g_sweeps, 0);
}
//+------------------------------------------------------------------+
