//+------------------------------------------------------------------+
//|                                          MarketCycleDetector.mq5  |
//|                        TradeMind Market Cycle Detection Indicator  |
//|  Detects the full SMC cycle: Range -> Sweep -> Displacement ->    |
//|  EQ Return -> EQ Decision -> Rotation -> Repeat.                  |
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
enum ENUM_CYCLE_STATE
{
   CYCLE_RANGING = 0,        // Range forming / established
   CYCLE_SWEEP,              // Liquidity swept at range extreme
   CYCLE_DISPLACEMENT,       // Strong candles away from sweep
   CYCLE_EQ_RETURN,          // Price returning to equilibrium
   CYCLE_EQ_DECISION,        // EQ rejection or break decided
   CYCLE_COMPLETED,          // Full rotation complete
   CYCLE_INVALIDATED,        // Cycle broke down
};

enum ENUM_SWEEP_SIDE
{
   SWEEP_BUY_SIDE = 0,       // Swept above range high (buy-side liquidity)
   SWEEP_SELL_SIDE,           // Swept below range low (sell-side liquidity)
};

enum ENUM_EQ_OUTCOME
{
   EQ_NONE = 0,              // No decision yet
   EQ_REJECTION,              // Rejected at EQ — continuation
   EQ_BREAK,                  // Broke through EQ — new range
};

//+------------------------------------------------------------------+
//| Input Parameters                                                   |
//+------------------------------------------------------------------+
input group "=== Range Detection ==="
input int      InpSwingStrength      = 3;       // Swing strength (bars each side)
input int      InpMaxBars            = 500;     // Max bars to analyze
input int      InpATRPeriod          = 14;      // ATR period
input double   InpEqualTolerance     = 0.3;     // Equal level tolerance (x ATR)
input int      InpMinRangeBars       = 10;      // Minimum bars for valid range
input double   InpMinRangeATR        = 0.5;     // Min range width (x ATR)
input double   InpMaxRangeATR        = 3.0;     // Max range width (x ATR)
input double   InpContainment        = 0.60;    // Min bar containment ratio (0-1)
input int      InpMinClusterTouches  = 2;       // Min touches for high/low cluster

input group "=== Level & Sweep Detection ==="
input int      InpMinLevelTouches    = 2;       // Min touches to form a level (1=all swings)
input int      InpSweepLookback      = 30;      // Bars after level to scan for sweep
input double   InpSweepWickMinATR    = 0.02;    // Min wick beyond level (x ATR, 0=any)

input group "=== Cycle Detection ==="
input double   InpDisplacementRatio  = 0.6;     // Min body/range for displacement candle
input int      InpMinDispCandles     = 1;       // Min displacement candles needed
input int      InpMaxBarsAfterSweep  = 15;      // Window to find displacement after sweep
input int      InpMaxBarsEQReturn    = 30;      // Window for EQ return after displacement
input double   InpEQTolerance        = 0.2;     // EQ zone tolerance (x range width)

input group "=== Alerts ==="
input bool     InpAlertOnSweep       = true;    // Alert on sweep detection
input bool     InpAlertOnDisplacement = false;   // Alert on displacement
input bool     InpAlertOnEQDecision  = true;    // Alert on EQ rejection/break
input bool     InpAlertPopup         = true;    // Alert: Popup dialog
input bool     InpAlertSound         = true;    // Alert: Play sound
input bool     InpAlertPush          = false;   // Alert: Push notification

input group "=== Visual ==="
input bool     InpShowRangeBoxes     = true;    // Show range rectangles
input bool     InpShowEQLine         = true;    // Show EQ dashed line
input bool     InpShowLevels         = true;    // Show support/resistance level lines
input bool     InpShowSweepMarkers   = true;    // Show sweep arrows + labels
input bool     InpShowDisplacement   = true;    // Show displacement markers
input bool     InpShowEQMarkers      = true;    // Show EQ interaction markers
input bool     InpShowPhaseLabels    = true;    // Show current phase label
input bool     InpShowDashboard      = true;    // Show dashboard (Comment)
input int      InpMaxCyclesDisplay   = 5;       // Max historical cycles to display
input int      InpMaxSweepsDisplay   = 30;      // Max past sweeps to show
input int      InpMaxLevelsDisplay   = 20;      // Max levels to draw
input int      InpFontSize           = 8;       // Label font size

input group "=== Colors ==="
input color    InpRangeColor         = clrGold;          // Range box color (completed)
input color    InpRangeActiveColor   = clrDodgerBlue;    // Active range box color
input color    InpEQLineColor        = clrSilver;        // EQ line color
input color    InpSupportColor       = clrDodgerBlue;    // Support/demand level color
input color    InpResistanceColor    = clrOrangeRed;     // Resistance/supply level color
input color    InpSweepBuyColor      = clrOrangeRed;     // Buy-side sweep color
input color    InpSweepSellColor     = clrDodgerBlue;    // Sell-side sweep color
input color    InpDispBullColor      = clrLime;          // Bullish displacement
input color    InpDispBearColor      = clrRed;           // Bearish displacement
input color    InpEQRejColor         = clrLime;          // EQ rejection color
input color    InpEQBrkColor         = clrOrangeRed;     // EQ break color
input color    InpCompletedColor     = clrMediumPurple;  // Completed cycle color
input color    InpInvalidColor       = clrDimGray;       // Invalidated cycle color

//+------------------------------------------------------------------+
//| Structs                                                            |
//+------------------------------------------------------------------+
struct SwingPoint
{
   int            bar;
   double         price;
   bool           isHigh;
   datetime       time;
};

struct CycleRange
{
   //--- Range definition
   double         rangeHigh;
   double         rangeLow;
   double         rangeEQ;
   int            rangeStartBar;
   int            rangeEndBar;
   datetime       rangeStartTime;
   datetime       rangeEndTime;
   int            highTouches;
   int            lowTouches;

   //--- Current state
   ENUM_CYCLE_STATE  state;
   ENUM_SWEEP_SIDE   sweepSide;
   ENUM_EQ_OUTCOME   eqOutcome;

   //--- Sweep data
   int            sweepBar;
   datetime       sweepTime;
   double         sweepWickPrice;
   double         sweepClosePrice;

   //--- Displacement data
   int            dispBar;
   datetime       dispTime;
   double         dispClosePrice;
   int            dispCandleCount;

   //--- EQ Return data
   int            eqReturnBar;
   datetime       eqReturnTime;

   //--- EQ Decision data
   int            eqDecisionBar;
   datetime       eqDecisionTime;

   //--- Completion
   int            completionBar;
   datetime       completionTime;

   //--- Alert tracking
   bool           alertFiredSweep;
   bool           alertFiredDisp;
   bool           alertFiredEQ;
};

struct SweepEvent
{
   datetime       time;
   double         wickPrice;
   double         closePrice;
   ENUM_SWEEP_SIDE side;
   double         rangeHigh;
   double         rangeLow;
};

struct LiquidityLevel
{
   double         price;
   int            touches;
   int            oldestBar;       // highest index = oldest in series
   int            newestBar;       // lowest index = newest in series
   datetime       oldestTime;
   datetime       newestTime;
   bool           isResistance;    // true = resistance/supply, false = support/demand
   bool           swept;
   datetime       sweepTime;
   double         sweepWickPrice;
   bool           broken;          // close went through significantly (not a sweep)
};

//+------------------------------------------------------------------+
//| Globals                                                            |
//+------------------------------------------------------------------+
string         g_objPrefix = "MCD_";
int            g_lastCalculatedBars = 0;
double         g_atrValue = 0;

SwingPoint     g_swingHighs[];
SwingPoint     g_swingLows[];
int            g_shCount = 0;
int            g_slCount = 0;

LiquidityLevel g_levels[];
int            g_levelCount = 0;

CycleRange     g_cycles[];
int            g_cycleCount = 0;

SweepEvent     g_sweeps[];
int            g_sweepCount = 0;

//+------------------------------------------------------------------+
//| OnInit                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   CleanAllObjects();
   Comment("");
   g_sweepCount = 0;
   ArrayResize(g_sweeps, 0);
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
   if(rates_total < InpATRPeriod + InpSwingStrength + InpMinRangeBars + 10)
      return rates_total;

   //--- New bar guard
   if(rates_total == g_lastCalculatedBars) return rates_total;
   g_lastCalculatedBars = rates_total;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int startBar = MathMin(InpMaxBars, rates_total - 1);

   //--- 1. Calculate ATR
   g_atrValue = CalculateATR(high, low, close, rates_total);
   if(g_atrValue <= 0) return rates_total;

   //--- 2. Detect swing points
   g_shCount = 0;
   g_slCount = 0;
   DetectSwingPoints(high, low, time, startBar);

   //--- 2b. Detect support/resistance levels and their sweeps
   DetectLiquidityLevels(high, low, close, time, startBar);

   //--- 3. Detect ranges from swing clusters
   g_cycleCount = 0;
   DetectRanges(high, low, close, time, startBar);

   //--- 4. Process state machine for each cycle
   for(int i = 0; i < g_cycleCount; i++)
      ProcessCycleStateMachine(i, open, high, low, close, time, startBar);

   //--- 4b. Collect sweeps into persistent storage
   CollectSweeps();

   //--- 5. Check alerts
   CheckAlerts();

   //--- 6. Draw everything
   CleanAllObjects();
   DrawAllObjects(time, open, close, high, low, startBar);

   //--- 7. Dashboard
   if(InpShowDashboard)
      BuildDashboard();

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
//| DetectSwingPoints — N-bar swing highs and lows                     |
//+------------------------------------------------------------------+
void DetectSwingPoints(const double &high[], const double &low[],
                       const datetime &time[], int maxBar)
{
   int maxSwings = maxBar;
   ArrayResize(g_swingHighs, maxSwings);
   ArrayResize(g_swingLows, maxSwings);

   for(int i = InpSwingStrength; i <= maxBar - InpSwingStrength; i++)
   {
      //--- Swing high
      bool isSwingHigh = true;
      for(int j = 1; j <= InpSwingStrength; j++)
      {
         if(high[i] <= high[i - j] || high[i] <= high[i + j])
         { isSwingHigh = false; break; }
      }
      if(isSwingHigh && g_shCount < maxSwings)
      {
         g_swingHighs[g_shCount].bar    = i;
         g_swingHighs[g_shCount].price  = high[i];
         g_swingHighs[g_shCount].isHigh = true;
         g_swingHighs[g_shCount].time   = time[i];
         g_shCount++;
      }

      //--- Swing low
      bool isSwingLow = true;
      for(int j = 1; j <= InpSwingStrength; j++)
      {
         if(low[i] >= low[i - j] || low[i] >= low[i + j])
         { isSwingLow = false; break; }
      }
      if(isSwingLow && g_slCount < maxSwings)
      {
         g_swingLows[g_slCount].bar    = i;
         g_swingLows[g_slCount].price  = low[i];
         g_swingLows[g_slCount].isHigh = false;
         g_swingLows[g_slCount].time   = time[i];
         g_slCount++;
      }
   }
   ArrayResize(g_swingHighs, g_shCount);
   ArrayResize(g_swingLows, g_slCount);
}

//+------------------------------------------------------------------+
//| DetectRanges — find consolidation zones from swing clusters        |
//+------------------------------------------------------------------+
void DetectRanges(const double &high[], const double &low[],
                  const double &close[], const datetime &time[], int maxBar)
{
   double tol = g_atrValue * InpEqualTolerance;
   int maxCycles = 50;
   ArrayResize(g_cycles, maxCycles);

   //--- Cluster swing highs into levels
   double   shLevels[];
   int      shBars[];      // oldest bar of cluster
   int      shEndBars[];   // newest bar of cluster
   datetime shTimes[];
   datetime shEndTimes[];
   int      shTouches[];
   int      shLevelCount = 0;
   bool     shUsed[];
   ArrayResize(shUsed, g_shCount);
   ArrayInitialize(shUsed, false);
   ArrayResize(shLevels, g_shCount);
   ArrayResize(shBars, g_shCount);
   ArrayResize(shEndBars, g_shCount);
   ArrayResize(shTimes, g_shCount);
   ArrayResize(shEndTimes, g_shCount);
   ArrayResize(shTouches, g_shCount);

   for(int i = 0; i < g_shCount; i++)
   {
      if(shUsed[i]) continue;

      double anchorPrice = g_swingHighs[i].price;
      double levelPrice = anchorPrice;
      int touches = 1;
      int oldestBar = g_swingHighs[i].bar;
      int newestBar = g_swingHighs[i].bar;
      datetime oldestTime = g_swingHighs[i].time;
      datetime newestTime = g_swingHighs[i].time;

      for(int j = i + 1; j < g_shCount; j++)
      {
         if(shUsed[j]) continue;
         if(MathAbs(g_swingHighs[j].price - anchorPrice) <= tol)
         {
            touches++;
            shUsed[j] = true;
            levelPrice = (levelPrice * (touches - 1) + g_swingHighs[j].price) / touches;
            if(g_swingHighs[j].bar > oldestBar) { oldestBar = g_swingHighs[j].bar; oldestTime = g_swingHighs[j].time; }
            if(g_swingHighs[j].bar < newestBar) { newestBar = g_swingHighs[j].bar; newestTime = g_swingHighs[j].time; }
         }
      }

      if(touches >= InpMinClusterTouches)
      {
         shLevels[shLevelCount]   = levelPrice;
         shBars[shLevelCount]     = oldestBar;
         shEndBars[shLevelCount]  = newestBar;
         shTimes[shLevelCount]    = oldestTime;
         shEndTimes[shLevelCount] = newestTime;
         shTouches[shLevelCount]  = touches;
         shLevelCount++;
      }
   }

   //--- Cluster swing lows into levels
   double   slLevels[];
   int      slBars[];
   int      slEndBars[];
   datetime slTimes[];
   datetime slEndTimes[];
   int      slTouches[];
   int      slLevelCount = 0;
   bool     slUsed[];
   ArrayResize(slUsed, g_slCount);
   ArrayInitialize(slUsed, false);
   ArrayResize(slLevels, g_slCount);
   ArrayResize(slBars, g_slCount);
   ArrayResize(slEndBars, g_slCount);
   ArrayResize(slTimes, g_slCount);
   ArrayResize(slEndTimes, g_slCount);
   ArrayResize(slTouches, g_slCount);

   for(int i = 0; i < g_slCount; i++)
   {
      if(slUsed[i]) continue;

      double anchorPrice = g_swingLows[i].price;
      double levelPrice = anchorPrice;
      int touches = 1;
      int oldestBar = g_swingLows[i].bar;
      int newestBar = g_swingLows[i].bar;
      datetime oldestTime = g_swingLows[i].time;
      datetime newestTime = g_swingLows[i].time;

      for(int j = i + 1; j < g_slCount; j++)
      {
         if(slUsed[j]) continue;
         if(MathAbs(g_swingLows[j].price - anchorPrice) <= tol)
         {
            touches++;
            slUsed[j] = true;
            levelPrice = (levelPrice * (touches - 1) + g_swingLows[j].price) / touches;
            if(g_swingLows[j].bar > oldestBar) { oldestBar = g_swingLows[j].bar; oldestTime = g_swingLows[j].time; }
            if(g_swingLows[j].bar < newestBar) { newestBar = g_swingLows[j].bar; newestTime = g_swingLows[j].time; }
         }
      }

      if(touches >= InpMinClusterTouches)
      {
         slLevels[slLevelCount]   = levelPrice;
         slBars[slLevelCount]     = oldestBar;
         slEndBars[slLevelCount]  = newestBar;
         slTimes[slLevelCount]    = oldestTime;
         slEndTimes[slLevelCount] = newestTime;
         slTouches[slLevelCount]  = touches;
         slLevelCount++;
      }
   }

   //--- Pair high clusters with low clusters to form ranges
   for(int hi = 0; hi < shLevelCount; hi++)
   {
      for(int li = 0; li < slLevelCount; li++)
      {
         if(g_cycleCount >= maxCycles) break;

         double rHigh = shLevels[hi];
         double rLow  = slLevels[li];
         if(rHigh <= rLow) continue;

         double width = rHigh - rLow;

         //--- Width validation
         if(width < g_atrValue * InpMinRangeATR) continue;
         if(width > g_atrValue * InpMaxRangeATR) continue;

         //--- Temporal overlap between high and low clusters
         //--- In series mode: higher bar index = older bar
         int overlapOldest = MathMin(shBars[hi], slBars[li]);     // more recent of two starts
         int overlapNewest = MathMax(shEndBars[hi], slEndBars[li]); // older of two ends
         int overlapBars   = overlapOldest - overlapNewest;

         //--- Require temporal overlap (allow tiny gap of ≤5 bars)
         if(overlapBars < -5) continue;

         //--- Full span for range box display
         int oldestBar = MathMax(shBars[hi], slBars[li]);
         int newestBar = MathMin(shEndBars[hi], slEndBars[li]);
         int barSpan = oldestBar - newestBar;
         if(barSpan < InpMinRangeBars) continue;

         //--- Containment check (use overlap region if exists, else full span)
         int contOldest = (overlapBars > 0) ? overlapOldest : oldestBar;
         int contNewest = (overlapBars > 0) ? overlapNewest : newestBar;
         int contained = 0;
         int tested = 0;
         for(int b = contOldest; b >= contNewest; b--)
         {
            tested++;
            if(high[b] <= rHigh + tol && low[b] >= rLow - tol)
               contained++;
         }
         if(tested == 0) continue;
         if((double)contained / tested < InpContainment) continue;

         //--- Deduplication: skip if overlaps >50% with existing range
         bool duplicate = false;
         for(int c = 0; c < g_cycleCount; c++)
         {
            int dedupOverlap = MathMax(0, MathMin(oldestBar, g_cycles[c].rangeStartBar)
                                          - MathMax(newestBar, g_cycles[c].rangeEndBar));
            int thisSpan     = oldestBar - newestBar;

            if(thisSpan > 0 && dedupOverlap > thisSpan * 0.5)
            {
               //--- Also check price overlap
               double priceOverlap = MathMin(rHigh, g_cycles[c].rangeHigh)
                                   - MathMax(rLow, g_cycles[c].rangeLow);
               if(priceOverlap > width * 0.5)
               { duplicate = true; break; }
            }
         }
         if(duplicate) continue;

         //--- Create the cycle range
         CycleRange cr;
         cr.rangeHigh      = rHigh;
         cr.rangeLow       = rLow;
         cr.rangeEQ        = (rHigh + rLow) / 2.0;
         cr.rangeStartBar  = oldestBar;
         cr.rangeEndBar    = newestBar;
         cr.rangeStartTime = time[oldestBar];
         cr.rangeEndTime   = time[newestBar];
         cr.highTouches    = shTouches[hi];
         cr.lowTouches     = slTouches[li];
         cr.state          = CYCLE_RANGING;
         cr.sweepSide      = SWEEP_BUY_SIDE;
         cr.eqOutcome      = EQ_NONE;
         cr.sweepBar       = 0;
         cr.sweepTime      = 0;
         cr.sweepWickPrice  = 0;
         cr.sweepClosePrice = 0;
         cr.dispBar         = 0;
         cr.dispTime        = 0;
         cr.dispClosePrice  = 0;
         cr.dispCandleCount = 0;
         cr.eqReturnBar     = 0;
         cr.eqReturnTime    = 0;
         cr.eqDecisionBar   = 0;
         cr.eqDecisionTime  = 0;
         cr.completionBar   = 0;
         cr.completionTime  = 0;
         cr.alertFiredSweep = false;
         cr.alertFiredDisp  = false;
         cr.alertFiredEQ    = false;

         g_cycles[g_cycleCount] = cr;
         g_cycleCount++;
      }
      if(g_cycleCount >= maxCycles) break;
   }
   ArrayResize(g_cycles, g_cycleCount);
}

//+------------------------------------------------------------------+
//| ProcessCycleStateMachine — advance cycle through phases            |
//+------------------------------------------------------------------+
void ProcessCycleStateMachine(int idx,
                               const double &open[], const double &high[],
                               const double &low[], const double &close[],
                               const datetime &time[], int maxBar)
{
   double rHigh = g_cycles[idx].rangeHigh;
   double rLow  = g_cycles[idx].rangeLow;
   double rEQ   = g_cycles[idx].rangeEQ;
   double rWidth = rHigh - rLow;
   double sweepTol = g_atrValue * 0.05;

   //=== STATE: RANGING → SWEEP ===
   if(g_cycles[idx].state == CYCLE_RANGING)
   {
      //--- Scan bars from rangeEndBar toward current (newer bars)
      int scanStart = g_cycles[idx].rangeEndBar - 1;
      if(scanStart < 1) scanStart = 1;

      for(int b = scanStart; b >= 1; b--)
      {
         //--- Buy-side sweep: wick above range high, close inside
         if(high[b] > rHigh + sweepTol && close[b] < rHigh)
         {
            g_cycles[idx].state          = CYCLE_SWEEP;
            g_cycles[idx].sweepSide      = SWEEP_BUY_SIDE;
            g_cycles[idx].sweepBar       = b;
            g_cycles[idx].sweepTime      = time[b];
            g_cycles[idx].sweepWickPrice  = high[b];
            g_cycles[idx].sweepClosePrice = close[b];
            break;
         }
         //--- Sell-side sweep: wick below range low, close inside
         if(low[b] < rLow - sweepTol && close[b] > rLow)
         {
            g_cycles[idx].state          = CYCLE_SWEEP;
            g_cycles[idx].sweepSide      = SWEEP_SELL_SIDE;
            g_cycles[idx].sweepBar       = b;
            g_cycles[idx].sweepTime      = time[b];
            g_cycles[idx].sweepWickPrice  = low[b];
            g_cycles[idx].sweepClosePrice = close[b];
            break;
         }
      }
   }

   //=== STATE: SWEEP → DISPLACEMENT ===
   if(g_cycles[idx].state == CYCLE_SWEEP)
   {
      int scanStart = g_cycles[idx].sweepBar - 1;
      int scanEnd   = MathMax(1, g_cycles[idx].sweepBar - InpMaxBarsAfterSweep);
      int dispCount = 0;
      int firstDispBar = 0;
      datetime firstDispTime = 0;
      double firstDispClose = 0;

      for(int b = scanStart; b >= scanEnd; b--)
      {
         double range = high[b] - low[b];
         if(range <= 0) continue;
         double body = MathAbs(close[b] - open[b]);
         if(body / range < InpDisplacementRatio) continue;

         //--- Direction must oppose sweep
         bool isBullCandle = (close[b] > open[b]);
         if(g_cycles[idx].sweepSide == SWEEP_BUY_SIDE && isBullCandle) continue;
         if(g_cycles[idx].sweepSide == SWEEP_SELL_SIDE && !isBullCandle) continue;

         dispCount++;
         if(firstDispBar == 0)
         {
            firstDispBar   = b;
            firstDispTime  = time[b];
            firstDispClose = close[b];
         }
      }

      if(dispCount >= InpMinDispCandles && firstDispBar > 0)
      {
         //--- Validate displacement moved meaningfully
         bool meaningful = false;
         if(g_cycles[idx].sweepSide == SWEEP_BUY_SIDE)
            meaningful = (firstDispClose < rHigh - rWidth * 0.3);
         else
            meaningful = (firstDispClose > rLow + rWidth * 0.3);

         if(meaningful)
         {
            g_cycles[idx].state          = CYCLE_DISPLACEMENT;
            g_cycles[idx].dispBar        = firstDispBar;
            g_cycles[idx].dispTime       = firstDispTime;
            g_cycles[idx].dispClosePrice = firstDispClose;
            g_cycles[idx].dispCandleCount = dispCount;
         }
      }

      //--- Check invalidation: sweep became real breakout
      for(int b = scanStart; b >= scanEnd; b--)
      {
         if(g_cycles[idx].sweepSide == SWEEP_BUY_SIDE && close[b] > rHigh + rWidth * 0.5)
         { g_cycles[idx].state = CYCLE_INVALIDATED; return; }
         if(g_cycles[idx].sweepSide == SWEEP_SELL_SIDE && close[b] < rLow - rWidth * 0.5)
         { g_cycles[idx].state = CYCLE_INVALIDATED; return; }
      }
   }

   //=== STATE: DISPLACEMENT → EQ_RETURN ===
   if(g_cycles[idx].state == CYCLE_DISPLACEMENT)
   {
      int scanStart = g_cycles[idx].dispBar - 1;
      int scanEnd   = MathMax(1, g_cycles[idx].dispBar - InpMaxBarsEQReturn);

      double eqZoneHigh = rEQ + rWidth * InpEQTolerance;
      double eqZoneLow  = rEQ - rWidth * InpEQTolerance;

      for(int b = scanStart; b >= scanEnd; b--)
      {
         double bodyTop = MathMax(open[b], close[b]);
         double bodyBot = MathMin(open[b], close[b]);

         //--- Check if candle body or close enters EQ zone
         if(bodyTop >= eqZoneLow && bodyBot <= eqZoneHigh)
         {
            g_cycles[idx].state       = CYCLE_EQ_RETURN;
            g_cycles[idx].eqReturnBar = b;
            g_cycles[idx].eqReturnTime = time[b];
            break;
         }
      }

      //--- Check invalidation
      for(int b = scanStart; b >= scanEnd; b--)
      {
         if(g_cycles[idx].sweepSide == SWEEP_BUY_SIDE && close[b] > rHigh + rWidth * 0.5)
         { g_cycles[idx].state = CYCLE_INVALIDATED; return; }
         if(g_cycles[idx].sweepSide == SWEEP_SELL_SIDE && close[b] < rLow - rWidth * 0.5)
         { g_cycles[idx].state = CYCLE_INVALIDATED; return; }
      }
   }

   //=== STATE: EQ_RETURN → EQ_DECISION ===
   if(g_cycles[idx].state == CYCLE_EQ_RETURN)
   {
      double eqZoneHigh = rEQ + rWidth * InpEQTolerance;
      double eqZoneLow  = rEQ - rWidth * InpEQTolerance;

      //--- Check EQ return bar and up to 5 bars after
      int startCheck = g_cycles[idx].eqReturnBar;
      int endCheck   = MathMax(1, startCheck - 5);

      for(int b = startCheck; b >= endCheck; b--)
      {
         if(g_cycles[idx].sweepSide == SWEEP_SELL_SIDE)
         {
            //--- After sell-side sweep + bullish displacement:
            //--- Rejection = touches EQ zone, close stays ABOVE EQ
            if(low[b] <= eqZoneHigh && close[b] > rEQ)
            {
               g_cycles[idx].state          = CYCLE_EQ_DECISION;
               g_cycles[idx].eqOutcome      = EQ_REJECTION;
               g_cycles[idx].eqDecisionBar  = b;
               g_cycles[idx].eqDecisionTime = time[b];
               break;
            }
            //--- Break = close passes below EQ zone
            if(close[b] < eqZoneLow)
            {
               g_cycles[idx].state          = CYCLE_EQ_DECISION;
               g_cycles[idx].eqOutcome      = EQ_BREAK;
               g_cycles[idx].eqDecisionBar  = b;
               g_cycles[idx].eqDecisionTime = time[b];
               break;
            }
         }
         else // SWEEP_BUY_SIDE
         {
            //--- After buy-side sweep + bearish displacement:
            //--- Rejection = touches EQ zone, close stays BELOW EQ
            if(high[b] >= eqZoneLow && close[b] < rEQ)
            {
               g_cycles[idx].state          = CYCLE_EQ_DECISION;
               g_cycles[idx].eqOutcome      = EQ_REJECTION;
               g_cycles[idx].eqDecisionBar  = b;
               g_cycles[idx].eqDecisionTime = time[b];
               break;
            }
            //--- Break = close passes above EQ zone
            if(close[b] > eqZoneHigh)
            {
               g_cycles[idx].state          = CYCLE_EQ_DECISION;
               g_cycles[idx].eqOutcome      = EQ_BREAK;
               g_cycles[idx].eqDecisionBar  = b;
               g_cycles[idx].eqDecisionTime = time[b];
               break;
            }
         }
      }
   }

   //=== STATE: EQ_DECISION → COMPLETED ===
   if(g_cycles[idx].state == CYCLE_EQ_DECISION)
   {
      g_cycles[idx].state          = CYCLE_COMPLETED;
      g_cycles[idx].completionBar  = g_cycles[idx].eqDecisionBar;
      g_cycles[idx].completionTime = g_cycles[idx].eqDecisionTime;
   }
}

//+------------------------------------------------------------------+
//| CheckAlerts — fire alerts on state transitions                     |
//+------------------------------------------------------------------+
void CheckAlerts()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = 0; i < g_cycleCount; i++)
   {
      //--- Sweep alert (only for recent events, bar <= 3)
      if(InpAlertOnSweep && g_cycles[i].state >= CYCLE_SWEEP
         && !g_cycles[i].alertFiredSweep && g_cycles[i].sweepBar <= 3)
      {
         string side = (g_cycles[i].sweepSide == SWEEP_BUY_SIDE) ? "BUY-SIDE" : "SELL-SIDE";
         FireAlert("MCD | " + _Symbol + " " + GetTimeframeString()
                  + " | " + side + " SWEEP @ "
                  + DoubleToString(g_cycles[i].sweepWickPrice, digits));
         g_cycles[i].alertFiredSweep = true;
      }

      //--- Displacement alert
      if(InpAlertOnDisplacement && g_cycles[i].state >= CYCLE_DISPLACEMENT
         && !g_cycles[i].alertFiredDisp && g_cycles[i].dispBar <= 3)
      {
         FireAlert("MCD | " + _Symbol + " " + GetTimeframeString()
                  + " | DISPLACEMENT detected");
         g_cycles[i].alertFiredDisp = true;
      }

      //--- EQ Decision alert
      if(InpAlertOnEQDecision && g_cycles[i].state >= CYCLE_EQ_DECISION
         && !g_cycles[i].alertFiredEQ && g_cycles[i].eqDecisionBar <= 3)
      {
         string outcome = (g_cycles[i].eqOutcome == EQ_REJECTION) ? "EQ REJECTION" : "EQ BREAK";
         FireAlert("MCD | " + _Symbol + " " + GetTimeframeString()
                  + " | " + outcome);
         g_cycles[i].alertFiredEQ = true;
      }
   }
}

//+------------------------------------------------------------------+
//| FireAlert — send alert via configured channels                     |
//+------------------------------------------------------------------+
void FireAlert(string message)
{
   if(InpAlertPopup) Alert(message);
   if(InpAlertSound) PlaySound("alert2.wav");
   if(InpAlertPush)  SendNotification(message);
}

//+------------------------------------------------------------------+
//| CollectSweeps — accumulate sweeps into persistent storage          |
//+------------------------------------------------------------------+
void CollectSweeps()
{
   for(int i = 0; i < g_cycleCount; i++)
   {
      if(g_cycles[i].state < CYCLE_SWEEP) continue;
      if(g_cycles[i].sweepTime == 0) continue;

      //--- Deduplicate by time + side
      bool found = false;
      for(int j = 0; j < g_sweepCount; j++)
      {
         if(g_sweeps[j].time == g_cycles[i].sweepTime
            && g_sweeps[j].side == g_cycles[i].sweepSide)
         { found = true; break; }
      }
      if(found) continue;

      //--- Add new sweep
      g_sweepCount++;
      ArrayResize(g_sweeps, g_sweepCount);
      g_sweeps[g_sweepCount - 1].time       = g_cycles[i].sweepTime;
      g_sweeps[g_sweepCount - 1].wickPrice   = g_cycles[i].sweepWickPrice;
      g_sweeps[g_sweepCount - 1].closePrice  = g_cycles[i].sweepClosePrice;
      g_sweeps[g_sweepCount - 1].side        = g_cycles[i].sweepSide;
      g_sweeps[g_sweepCount - 1].rangeHigh   = g_cycles[i].rangeHigh;
      g_sweeps[g_sweepCount - 1].rangeLow    = g_cycles[i].rangeLow;
   }

   //--- Trim oldest if exceeding 2x display limit
   if(g_sweepCount > InpMaxSweepsDisplay * 2)
   {
      int remove = g_sweepCount - InpMaxSweepsDisplay;
      for(int i = 0; i < g_sweepCount - remove; i++)
         g_sweeps[i] = g_sweeps[i + remove];
      g_sweepCount -= remove;
      ArrayResize(g_sweeps, g_sweepCount);
   }
}

//+------------------------------------------------------------------+
//| DetectLiquidityLevels — cluster swings into support/resistance,    |
//|  then detect sweeps of each level. Feeds g_levels[] and g_sweeps[] |
//+------------------------------------------------------------------+
void DetectLiquidityLevels(const double &high[], const double &low[],
                           const double &close[], const datetime &time[], int maxBar)
{
   double tol = g_atrValue * InpEqualTolerance;
   double sweepTol = g_atrValue * InpSweepWickMinATR;

   g_levelCount = 0;
   int maxLevels = 100;
   ArrayResize(g_levels, maxLevels);

   //=== CLUSTER SWING HIGHS → RESISTANCE/SUPPLY LEVELS ===
   bool shUsed[];
   ArrayResize(shUsed, g_shCount);
   ArrayInitialize(shUsed, false);

   for(int i = 0; i < g_shCount; i++)
   {
      if(shUsed[i]) continue;
      if(g_levelCount >= maxLevels) break;

      double anchorPrice = g_swingHighs[i].price;
      double levelPrice = anchorPrice;
      int touches = 1;
      int oldestBar = g_swingHighs[i].bar;
      int newestBar = g_swingHighs[i].bar;
      datetime oldestTime = g_swingHighs[i].time;
      datetime newestTime = g_swingHighs[i].time;

      for(int j = i + 1; j < g_shCount; j++)
      {
         if(shUsed[j]) continue;
         if(MathAbs(g_swingHighs[j].price - anchorPrice) <= tol)
         {
            touches++;
            shUsed[j] = true;
            levelPrice = (levelPrice * (touches - 1) + g_swingHighs[j].price) / touches;
            if(g_swingHighs[j].bar > oldestBar) { oldestBar = g_swingHighs[j].bar; oldestTime = g_swingHighs[j].time; }
            if(g_swingHighs[j].bar < newestBar) { newestBar = g_swingHighs[j].bar; newestTime = g_swingHighs[j].time; }
         }
      }

      if(touches >= InpMinLevelTouches)
      {
         g_levels[g_levelCount].price         = levelPrice;
         g_levels[g_levelCount].touches       = touches;
         g_levels[g_levelCount].oldestBar     = oldestBar;
         g_levels[g_levelCount].newestBar     = newestBar;
         g_levels[g_levelCount].oldestTime    = oldestTime;
         g_levels[g_levelCount].newestTime    = newestTime;
         g_levels[g_levelCount].isResistance  = true;
         g_levels[g_levelCount].swept         = false;
         g_levels[g_levelCount].sweepTime     = 0;
         g_levels[g_levelCount].sweepWickPrice = 0;
         g_levels[g_levelCount].broken        = false;
         g_levelCount++;
      }
   }

   //=== CLUSTER SWING LOWS → SUPPORT/DEMAND LEVELS ===
   bool slUsed[];
   ArrayResize(slUsed, g_slCount);
   ArrayInitialize(slUsed, false);

   for(int i = 0; i < g_slCount; i++)
   {
      if(slUsed[i]) continue;
      if(g_levelCount >= maxLevels) break;

      double anchorPrice = g_swingLows[i].price;
      double levelPrice = anchorPrice;
      int touches = 1;
      int oldestBar = g_swingLows[i].bar;
      int newestBar = g_swingLows[i].bar;
      datetime oldestTime = g_swingLows[i].time;
      datetime newestTime = g_swingLows[i].time;

      for(int j = i + 1; j < g_slCount; j++)
      {
         if(slUsed[j]) continue;
         if(MathAbs(g_swingLows[j].price - anchorPrice) <= tol)
         {
            touches++;
            slUsed[j] = true;
            levelPrice = (levelPrice * (touches - 1) + g_swingLows[j].price) / touches;
            if(g_swingLows[j].bar > oldestBar) { oldestBar = g_swingLows[j].bar; oldestTime = g_swingLows[j].time; }
            if(g_swingLows[j].bar < newestBar) { newestBar = g_swingLows[j].bar; newestTime = g_swingLows[j].time; }
         }
      }

      if(touches >= InpMinLevelTouches)
      {
         g_levels[g_levelCount].price         = levelPrice;
         g_levels[g_levelCount].touches       = touches;
         g_levels[g_levelCount].oldestBar     = oldestBar;
         g_levels[g_levelCount].newestBar     = newestBar;
         g_levels[g_levelCount].oldestTime    = oldestTime;
         g_levels[g_levelCount].newestTime    = newestTime;
         g_levels[g_levelCount].isResistance  = false;
         g_levels[g_levelCount].swept         = false;
         g_levels[g_levelCount].sweepTime     = 0;
         g_levels[g_levelCount].sweepWickPrice = 0;
         g_levels[g_levelCount].broken        = false;
         g_levelCount++;
      }
   }

   ArrayResize(g_levels, g_levelCount);

   //=== CHECK EACH LEVEL FOR SWEEP OR BREAK ===
   for(int i = 0; i < g_levelCount; i++)
   {
      int startScan = g_levels[i].newestBar - 1;
      if(startScan < 1) continue;
      int endScan = MathMax(1, startScan - InpSweepLookback);

      for(int b = startScan; b >= endScan; b--)
      {
         if(g_levels[i].isResistance)
         {
            //--- BSL sweep: wick above resistance, close back below
            if(high[b] > g_levels[i].price + sweepTol && close[b] < g_levels[i].price)
            {
               g_levels[i].swept          = true;
               g_levels[i].sweepTime      = time[b];
               g_levels[i].sweepWickPrice = high[b];

               //--- Feed into persistent g_sweeps[]
               bool found = false;
               for(int j = 0; j < g_sweepCount; j++)
               {
                  if(g_sweeps[j].time == time[b] && g_sweeps[j].side == SWEEP_BUY_SIDE)
                  { found = true; break; }
               }
               if(!found)
               {
                  g_sweepCount++;
                  ArrayResize(g_sweeps, g_sweepCount);
                  g_sweeps[g_sweepCount - 1].time       = time[b];
                  g_sweeps[g_sweepCount - 1].wickPrice   = high[b];
                  g_sweeps[g_sweepCount - 1].closePrice  = close[b];
                  g_sweeps[g_sweepCount - 1].side        = SWEEP_BUY_SIDE;
                  g_sweeps[g_sweepCount - 1].rangeHigh   = g_levels[i].price;
                  g_sweeps[g_sweepCount - 1].rangeLow    = 0;
               }
               break;
            }
            //--- Broken: close above by significant amount → real breakout
            if(close[b] > g_levels[i].price + g_atrValue * 0.3)
            { g_levels[i].broken = true; break; }
         }
         else // support/demand
         {
            //--- SSL sweep: wick below support, close back above
            if(low[b] < g_levels[i].price - sweepTol && close[b] > g_levels[i].price)
            {
               g_levels[i].swept          = true;
               g_levels[i].sweepTime      = time[b];
               g_levels[i].sweepWickPrice = low[b];

               bool found = false;
               for(int j = 0; j < g_sweepCount; j++)
               {
                  if(g_sweeps[j].time == time[b] && g_sweeps[j].side == SWEEP_SELL_SIDE)
                  { found = true; break; }
               }
               if(!found)
               {
                  g_sweepCount++;
                  ArrayResize(g_sweeps, g_sweepCount);
                  g_sweeps[g_sweepCount - 1].time       = time[b];
                  g_sweeps[g_sweepCount - 1].wickPrice   = low[b];
                  g_sweeps[g_sweepCount - 1].closePrice  = close[b];
                  g_sweeps[g_sweepCount - 1].side        = SWEEP_SELL_SIDE;
                  g_sweeps[g_sweepCount - 1].rangeHigh   = 0;
                  g_sweeps[g_sweepCount - 1].rangeLow    = g_levels[i].price;
               }
               break;
            }
            //--- Broken: close below significantly → real breakout
            if(close[b] < g_levels[i].price - g_atrValue * 0.3)
            { g_levels[i].broken = true; break; }
         }
      }
   }

   //--- Trim sweeps if too many
   if(g_sweepCount > InpMaxSweepsDisplay * 2)
   {
      int remove = g_sweepCount - InpMaxSweepsDisplay;
      for(int i = 0; i < g_sweepCount - remove; i++)
         g_sweeps[i] = g_sweeps[i + remove];
      g_sweepCount -= remove;
      ArrayResize(g_sweeps, g_sweepCount);
   }
}

//+------------------------------------------------------------------+
//| DrawLiquidityLevels — horizontal lines at support/resistance       |
//+------------------------------------------------------------------+
void DrawLiquidityLevels(const datetime &time[], int maxBar)
{
   int displayed = 0;

   //--- Draw newest levels first (iterate from end)
   for(int i = g_levelCount - 1; i >= 0 && displayed < InpMaxLevelsDisplay; i--)
   {
      //--- Skip broken levels (real breakout, not a sweep)
      if(g_levels[i].broken) continue;

      string nameLine = g_objPrefix + "LVL_" + IntegerToString(i);
      string nameLbl  = g_objPrefix + "LVLL_" + IntegerToString(i);

      //--- Level line: from formation to sweep or current bar
      datetime t1 = g_levels[i].oldestTime;
      datetime t2 = g_levels[i].swept ? g_levels[i].sweepTime : time[1];

      //--- Color and style based on state
      color clr;
      int style;

      if(g_levels[i].swept)
      {
         clr   = g_levels[i].isResistance ? InpSweepBuyColor : InpSweepSellColor;
         style = STYLE_DOT;
      }
      else
      {
         clr   = g_levels[i].isResistance ? InpResistanceColor : InpSupportColor;
         style = STYLE_SOLID;
      }

      //--- Draw level line
      if(!ObjectCreate(0, nameLine, OBJ_TREND, 0, t1, g_levels[i].price,
                       t2, g_levels[i].price))
      {
         ObjectMove(0, nameLine, 0, t1, g_levels[i].price);
         ObjectMove(0, nameLine, 1, t2, g_levels[i].price);
      }

      ObjectSetInteger(0, nameLine, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nameLine, OBJPROP_STYLE, style);
      ObjectSetInteger(0, nameLine, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nameLine, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nameLine, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, nameLine, OBJPROP_BACK, true);
      ObjectSetInteger(0, nameLine, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nameLine, OBJPROP_HIDDEN, true);

      //--- Label at the start of the level
      string typeLabel = g_levels[i].isResistance ? "RES" : "SUP";
      string text = typeLabel + "(" + IntegerToString(g_levels[i].touches) + ")";
      if(g_levels[i].swept) text += " SWEPT";

      double labelOffset = g_levels[i].isResistance ? g_atrValue * 0.05 : -g_atrValue * 0.05;
      int anchor = g_levels[i].isResistance ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER;

      if(!ObjectCreate(0, nameLbl, OBJ_TEXT, 0, t1, g_levels[i].price + labelOffset))
         ObjectMove(0, nameLbl, 0, t1, g_levels[i].price + labelOffset);

      ObjectSetString(0, nameLbl, OBJPROP_TEXT, text);
      ObjectSetInteger(0, nameLbl, OBJPROP_COLOR, clr);
      ObjectSetString(0, nameLbl, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, nameLbl, OBJPROP_FONTSIZE, InpFontSize - 1);
      ObjectSetInteger(0, nameLbl, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0, nameLbl, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nameLbl, OBJPROP_HIDDEN, true);

      displayed++;
   }
}

//+------------------------------------------------------------------+
//| DrawAllObjects — orchestrate all drawing                           |
//+------------------------------------------------------------------+
void DrawAllObjects(const datetime &time[], const double &open[],
                    const double &close[], const double &high[],
                    const double &low[], int maxBar)
{
   //--- Draw support/resistance levels
   if(InpShowLevels)        DrawLiquidityLevels(time, maxBar);

   //--- Draw persistent sweep arrows (from level sweeps + cycle sweeps)
   if(InpShowSweepMarkers)  DrawPersistentSweeps();

   //--- Draw cycle elements (range boxes, EQ, displacement, etc.)
   int startIdx = MathMax(0, g_cycleCount - InpMaxCyclesDisplay);

   for(int i = startIdx; i < g_cycleCount; i++)
   {
      int di = i - startIdx; // display index for object naming

      if(InpShowRangeBoxes)    DrawRangeBox(di, i, time, maxBar);
      if(InpShowEQLine)        DrawEQLine(di, i, time, maxBar);

      if(g_cycles[i].state >= CYCLE_DISPLACEMENT && g_cycles[i].state != CYCLE_INVALIDATED)
      {
         if(InpShowDisplacement)  DrawDisplacementMarker(di, i, time, high, low);
      }

      if(g_cycles[i].state >= CYCLE_EQ_DECISION && g_cycles[i].state != CYCLE_INVALIDATED)
      {
         if(InpShowEQMarkers)     DrawEQInteraction(di, i, time, high, low);
      }

      if(InpShowPhaseLabels)      DrawPhaseLabel(di, i, time);
   }
}

//+------------------------------------------------------------------+
//| DrawRangeBox — OBJ_RECTANGLE for range zone                        |
//+------------------------------------------------------------------+
void DrawRangeBox(int di, int ci, const datetime &time[], int maxBar)
{
   string name = g_objPrefix + "RNG_" + IntegerToString(di);
   datetime t1 = g_cycles[ci].rangeStartTime;
   datetime t2 = g_cycles[ci].rangeEndTime;

   //--- Extend active ranges to current bar
   if(g_cycles[ci].state < CYCLE_COMPLETED && g_cycles[ci].state != CYCLE_INVALIDATED)
      t2 = time[1];

   color clr = InpRangeColor;
   if(g_cycles[ci].state == CYCLE_INVALIDATED)
      clr = InpInvalidColor;
   else if(g_cycles[ci].state == CYCLE_COMPLETED)
      clr = InpCompletedColor;
   else
      clr = InpRangeActiveColor;

   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, g_cycles[ci].rangeHigh,
                    t2, g_cycles[ci].rangeLow))
      ObjectMove(0, name, 0, t1, g_cycles[ci].rangeHigh);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| DrawEQLine — dotted line at equilibrium                            |
//+------------------------------------------------------------------+
void DrawEQLine(int di, int ci, const datetime &time[], int maxBar)
{
   string name = g_objPrefix + "EQ_" + IntegerToString(di);
   datetime t1 = g_cycles[ci].rangeStartTime;
   datetime t2 = g_cycles[ci].rangeEndTime;

   if(g_cycles[ci].state < CYCLE_COMPLETED && g_cycles[ci].state != CYCLE_INVALIDATED)
      t2 = time[1];

   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, g_cycles[ci].rangeEQ,
                    t2, g_cycles[ci].rangeEQ))
   {
      ObjectMove(0, name, 0, t1, g_cycles[ci].rangeEQ);
      ObjectMove(0, name, 1, t2, g_cycles[ci].rangeEQ);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, InpEQLineColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| DrawPersistentSweeps — draw all accumulated sweeps                 |
//+------------------------------------------------------------------+
void DrawPersistentSweeps()
{
   int startIdx = MathMax(0, g_sweepCount - InpMaxSweepsDisplay);

   for(int i = startIdx; i < g_sweepCount; i++)
   {
      string suffix  = IntegerToString((long)g_sweeps[i].time);
      string nameArr = g_objPrefix + "SW_" + suffix;
      string nameLbl = g_objPrefix + "SWL_" + suffix;

      double yPrice;
      int arrowCode;
      color clr;
      string label;
      int anchor;

      if(g_sweeps[i].side == SWEEP_BUY_SIDE)
      {
         yPrice    = g_sweeps[i].wickPrice + g_atrValue * 0.1;
         arrowCode = 234; // down arrow
         clr       = InpSweepBuyColor;
         label     = "BSL SWEEP";
         anchor    = ANCHOR_LOWER;
      }
      else
      {
         yPrice    = g_sweeps[i].wickPrice - g_atrValue * 0.1;
         arrowCode = 233; // up arrow
         clr       = InpSweepSellColor;
         label     = "SSL SWEEP";
         anchor    = ANCHOR_UPPER;
      }

      //--- Arrow
      if(!ObjectCreate(0, nameArr, OBJ_ARROW, 0, g_sweeps[i].time, yPrice))
         ObjectMove(0, nameArr, 0, g_sweeps[i].time, yPrice);

      ObjectSetInteger(0, nameArr, OBJPROP_ARROWCODE, arrowCode);
      ObjectSetInteger(0, nameArr, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nameArr, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, nameArr, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nameArr, OBJPROP_HIDDEN, true);

      //--- Label
      double labelY = (g_sweeps[i].side == SWEEP_BUY_SIDE)
                      ? yPrice + g_atrValue * 0.15
                      : yPrice - g_atrValue * 0.15;

      if(!ObjectCreate(0, nameLbl, OBJ_TEXT, 0, g_sweeps[i].time, labelY))
         ObjectMove(0, nameLbl, 0, g_sweeps[i].time, labelY);

      ObjectSetString(0, nameLbl, OBJPROP_TEXT, label);
      ObjectSetInteger(0, nameLbl, OBJPROP_COLOR, clr);
      ObjectSetString(0, nameLbl, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, nameLbl, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetDouble(0, nameLbl, OBJPROP_ANGLE, 90.0);
      ObjectSetInteger(0, nameLbl, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0, nameLbl, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nameLbl, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| DrawDisplacementMarker — arrow + label on displacement candle       |
//+------------------------------------------------------------------+
void DrawDisplacementMarker(int di, int ci, const datetime &time[],
                            const double &high[], const double &low[])
{
   string nameArr = g_objPrefix + "DP_" + IntegerToString(di);
   string nameLbl = g_objPrefix + "DPL_" + IntegerToString(di);

   double yPrice;
   int arrowCode;
   color clr;
   int anchor;

   if(g_cycles[ci].sweepSide == SWEEP_BUY_SIDE)
   {
      //--- Bearish displacement after buy-side sweep
      yPrice    = low[g_cycles[ci].dispBar] - g_atrValue * 0.2;
      arrowCode = 234;
      clr       = InpDispBearColor;
      anchor    = ANCHOR_UPPER;
   }
   else
   {
      //--- Bullish displacement after sell-side sweep
      yPrice    = high[g_cycles[ci].dispBar] + g_atrValue * 0.2;
      arrowCode = 233;
      clr       = InpDispBullColor;
      anchor    = ANCHOR_LOWER;
   }

   //--- Arrow
   if(!ObjectCreate(0, nameArr, OBJ_ARROW, 0, g_cycles[ci].dispTime, yPrice))
      ObjectMove(0, nameArr, 0, g_cycles[ci].dispTime, yPrice);

   ObjectSetInteger(0, nameArr, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, nameArr, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nameArr, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nameArr, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nameArr, OBJPROP_HIDDEN, true);

   //--- Label
   double labelY = (g_cycles[ci].sweepSide == SWEEP_BUY_SIDE)
                   ? yPrice - g_atrValue * 0.1
                   : yPrice + g_atrValue * 0.1;

   if(!ObjectCreate(0, nameLbl, OBJ_TEXT, 0, g_cycles[ci].dispTime, labelY))
      ObjectMove(0, nameLbl, 0, g_cycles[ci].dispTime, labelY);

   ObjectSetString(0, nameLbl, OBJPROP_TEXT, "DISP");
   ObjectSetInteger(0, nameLbl, OBJPROP_COLOR, clr);
   ObjectSetString(0, nameLbl, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, nameLbl, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetDouble(0, nameLbl, OBJPROP_ANGLE, 90.0);
   ObjectSetInteger(0, nameLbl, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, nameLbl, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nameLbl, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| DrawEQInteraction — checkmark/X + label for EQ outcome             |
//+------------------------------------------------------------------+
void DrawEQInteraction(int di, int ci, const datetime &time[],
                       const double &high[], const double &low[])
{
   string nameArr = g_objPrefix + "EQD_" + IntegerToString(di);
   string nameLbl = g_objPrefix + "EQDL_" + IntegerToString(di);

   int arrowCode;
   color clr;
   string label;

   if(g_cycles[ci].eqOutcome == EQ_REJECTION)
   {
      arrowCode = 252; // checkmark
      clr       = InpEQRejColor;
      label     = "EQ REJ";
   }
   else
   {
      arrowCode = 251; // X mark
      clr       = InpEQBrkColor;
      label     = "EQ BRK";
   }

   double yPrice = g_cycles[ci].rangeEQ;

   //--- Arrow
   if(!ObjectCreate(0, nameArr, OBJ_ARROW, 0, g_cycles[ci].eqDecisionTime, yPrice))
      ObjectMove(0, nameArr, 0, g_cycles[ci].eqDecisionTime, yPrice);

   ObjectSetInteger(0, nameArr, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, nameArr, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nameArr, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, nameArr, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nameArr, OBJPROP_HIDDEN, true);

   //--- Label above the EQ arrow
   double labelY = yPrice + g_atrValue * 0.2;

   if(!ObjectCreate(0, nameLbl, OBJ_TEXT, 0, g_cycles[ci].eqDecisionTime, labelY))
      ObjectMove(0, nameLbl, 0, g_cycles[ci].eqDecisionTime, labelY);

   ObjectSetString(0, nameLbl, OBJPROP_TEXT, label);
   ObjectSetInteger(0, nameLbl, OBJPROP_COLOR, clr);
   ObjectSetString(0, nameLbl, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, nameLbl, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetDouble(0, nameLbl, OBJPROP_ANGLE, 90.0);
   ObjectSetInteger(0, nameLbl, OBJPROP_ANCHOR, ANCHOR_LOWER);
   ObjectSetInteger(0, nameLbl, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nameLbl, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| DrawPhaseLabel — current state text at range edge                  |
//+------------------------------------------------------------------+
void DrawPhaseLabel(int di, int ci, const datetime &time[])
{
   string name = g_objPrefix + "PH_" + IntegerToString(di);

   string phaseText;
   color  phaseColor;

   switch(g_cycles[ci].state)
   {
      case CYCLE_RANGING:       phaseText = "RANGING";    phaseColor = InpRangeActiveColor;  break;
      case CYCLE_SWEEP:         phaseText = "SWEEP";      phaseColor = (g_cycles[ci].sweepSide == SWEEP_BUY_SIDE) ? InpSweepBuyColor : InpSweepSellColor; break;
      case CYCLE_DISPLACEMENT:  phaseText = "DISP";       phaseColor = (g_cycles[ci].sweepSide == SWEEP_BUY_SIDE) ? InpDispBearColor : InpDispBullColor;  break;
      case CYCLE_EQ_RETURN:     phaseText = "EQ RET";     phaseColor = InpEQLineColor;       break;
      case CYCLE_EQ_DECISION:   phaseText = (g_cycles[ci].eqOutcome == EQ_REJECTION) ? "EQ REJ" : "EQ BRK";
                                phaseColor = (g_cycles[ci].eqOutcome == EQ_REJECTION) ? InpEQRejColor : InpEQBrkColor; break;
      case CYCLE_COMPLETED:     phaseText = "DONE";       phaseColor = InpCompletedColor;     break;
      case CYCLE_INVALIDATED:   phaseText = "INVALID";    phaseColor = InpInvalidColor;       break;
      default:                  phaseText = "??";         phaseColor = clrGray;               break;
   }

   //--- Position at the range end (newest bar) above the range
   datetime labelTime = g_cycles[ci].rangeEndTime;
   double   labelY    = g_cycles[ci].rangeHigh + g_atrValue * 0.3;

   if(!ObjectCreate(0, name, OBJ_TEXT, 0, labelTime, labelY))
      ObjectMove(0, name, 0, labelTime, labelY);

   ObjectSetString(0, name, OBJPROP_TEXT, phaseText);
   ObjectSetInteger(0, name, OBJPROP_COLOR, phaseColor);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize + 1);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LOWER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| BuildDashboard — Comment() with cycle stats                        |
//+------------------------------------------------------------------+
void BuildDashboard()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   string dash = "";
   string sep = "============================================================\n";

   dash += sep;
   dash += " MarketCycleDetector v1.0 | " + _Symbol + " " + GetTimeframeString() + "\n";
   dash += sep;

   //--- Count level stats
   int supCount = 0, resCount = 0, sweptCount = 0;
   for(int lv = 0; lv < g_levelCount; lv++)
   {
      if(g_levels[lv].broken) continue;
      if(g_levels[lv].isResistance) resCount++; else supCount++;
      if(g_levels[lv].swept) sweptCount++;
   }

   dash += " ATR(" + IntegerToString(InpATRPeriod) + "): "
         + DoubleToString(g_atrValue, digits)
         + " | Ranges: " + IntegerToString(g_cycleCount)
         + " | Levels: " + IntegerToString(supCount) + " SUP / "
         + IntegerToString(resCount) + " RES"
         + " | Swept: " + IntegerToString(sweptCount);

   //--- Count active
   int activeCount = 0;
   int completedCount = 0;
   int rejections = 0;
   int breaks = 0;
   for(int i = 0; i < g_cycleCount; i++)
   {
      if(g_cycles[i].state != CYCLE_COMPLETED && g_cycles[i].state != CYCLE_INVALIDATED)
         activeCount++;
      if(g_cycles[i].state == CYCLE_COMPLETED)
      {
         completedCount++;
         if(g_cycles[i].eqOutcome == EQ_REJECTION) rejections++;
         if(g_cycles[i].eqOutcome == EQ_BREAK) breaks++;
      }
   }
   dash += " | Active: " + IntegerToString(activeCount) + "\n\n";

   //--- Show recent cycles (newest first)
   int startIdx = MathMax(0, g_cycleCount - InpMaxCyclesDisplay);
   int displayNum = 1;
   for(int i = g_cycleCount - 1; i >= startIdx; i--)
   {
      string status;
      if(g_cycles[i].state == CYCLE_COMPLETED)
         status = "COMPLETED";
      else if(g_cycles[i].state == CYCLE_INVALIDATED)
         status = "INVALID";
      else
         status = "ACTIVE";

      dash += " #" + IntegerToString(displayNum) + " " + status
            + "  Range: " + DoubleToString(g_cycles[i].rangeLow, digits)
            + " - " + DoubleToString(g_cycles[i].rangeHigh, digits) + "\n";

      dash += "    EQ: " + DoubleToString(g_cycles[i].rangeEQ, digits)
            + "  W: " + DoubleToString(g_cycles[i].rangeHigh - g_cycles[i].rangeLow, digits)
            + " (" + DoubleToString((g_cycles[i].rangeHigh - g_cycles[i].rangeLow) / g_atrValue, 1) + "x ATR)"
            + "  H:" + IntegerToString(g_cycles[i].highTouches)
            + " L:" + IntegerToString(g_cycles[i].lowTouches) + "\n";

      //--- Checklist
      string check = "    ";
      check += "[X] Range";

      if(g_cycles[i].state >= CYCLE_SWEEP && g_cycles[i].state != CYCLE_INVALIDATED)
      {
         string side = (g_cycles[i].sweepSide == SWEEP_BUY_SIDE) ? "BSL" : "SSL";
         check += " [X] " + side + " Sweep";
      }
      else if(g_cycles[i].state != CYCLE_INVALIDATED)
         check += " [ ] Sweep";

      if(g_cycles[i].state >= CYCLE_DISPLACEMENT && g_cycles[i].state != CYCLE_INVALIDATED)
         check += " [X] Disp";
      else if(g_cycles[i].state < CYCLE_DISPLACEMENT && g_cycles[i].state != CYCLE_INVALIDATED)
         check += " [ ] Disp";

      if(g_cycles[i].state >= CYCLE_EQ_RETURN && g_cycles[i].state != CYCLE_INVALIDATED)
         check += " [X] EQ";
      else if(g_cycles[i].state < CYCLE_EQ_RETURN && g_cycles[i].state != CYCLE_INVALIDATED)
         check += " [ ] EQ";

      if(g_cycles[i].state >= CYCLE_EQ_DECISION && g_cycles[i].state != CYCLE_INVALIDATED)
      {
         string outcome = (g_cycles[i].eqOutcome == EQ_REJECTION) ? "Rej" : "Brk";
         check += " [X] " + outcome;
      }
      else if(g_cycles[i].state < CYCLE_EQ_DECISION && g_cycles[i].state != CYCLE_INVALIDATED)
         check += " [ ] Decision";

      dash += check + "\n";

      //--- Phase for active cycles
      if(g_cycles[i].state != CYCLE_COMPLETED && g_cycles[i].state != CYCLE_INVALIDATED)
      {
         string phase;
         switch(g_cycles[i].state)
         {
            case CYCLE_RANGING:      phase = "RANGING"; break;
            case CYCLE_SWEEP:        phase = "SWEEP detected, waiting for displacement"; break;
            case CYCLE_DISPLACEMENT: phase = "DISPLACED, waiting for EQ return"; break;
            case CYCLE_EQ_RETURN:    phase = "At EQ, waiting for decision"; break;
            default:                 phase = "Unknown"; break;
         }
         dash += "    Phase: " + phase + "\n";
      }

      dash += "\n";
      displayNum++;
   }

   //--- Stats
   if(completedCount > 0)
   {
      dash += " Stats: Completed: " + IntegerToString(completedCount)
            + " | EQ Rejections: " + IntegerToString(rejections)
            + " | EQ Breaks: " + IntegerToString(breaks) + "\n";
   }

   dash += sep;
   Comment(dash);
}

//+------------------------------------------------------------------+
//| GetTimeframeString — short TF label                                |
//+------------------------------------------------------------------+
string GetTimeframeString()
{
   switch(Period())
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return "??";
   }
}

//+------------------------------------------------------------------+
//| CleanAllObjects — remove MCD_ prefixed objects                     |
//+------------------------------------------------------------------+
void CleanAllObjects()
{
   ObjectsDeleteAll(0, g_objPrefix);
}
