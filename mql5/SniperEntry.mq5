//+------------------------------------------------------------------+
//|                                                  SniperEntry.mq5  |
//|                        TradeMind Sniper Entry Indicator            |
//|  Marks OB entry zones BEFORE price returns after sweep+disp.      |
//|  Includes trendline confluence and TP from opposing liquidity.     |
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

enum ENUM_ZONE_STATUS
{
   ZONE_PENDING = 0,     // OB identified, waiting for price to return
   ZONE_APPROACHING,     // Price within approach distance of entry
   ZONE_TRIGGERED,       // Price touched zone and held
   ZONE_HIT_TP,          // Take profit reached
   ZONE_HIT_SL,          // Stop loss hit
   ZONE_INVALIDATED,     // Zone broken or expired
};

enum ENUM_TP_TYPE
{
   TP_LIQUIDITY = 0,     // TP from opposing unswept liquidity
   TP_FALLBACK_RR,       // TP from fixed risk:reward ratio
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

struct EqualLevel
{
   double         price;
   int            startBar;
   int            endBar;
   datetime       startTime;
   datetime       endTime;
   int            touches;
   bool           isHigh;
   bool           swept;
   int            sweepBar;
   datetime       sweepTime;
};

struct SweepEvent
{
   int            bar;
   datetime       time;
   double         levelPrice;
   double         sweepPrice;
   ENUM_SWEEP_DIR direction;
   ENUM_SWEEP_CONTEXT context;
   bool           chochOccurred;
   int            displacementBar;
   datetime       displacementTime;
   double         displacementClose;
   int            obStartBar;
   double         obHigh;
   double         obLow;
   datetime       obStartTime;
};

struct TrendLine
{
   double         startPrice;
   datetime       startTime;
   int            startBar;
   double         endPrice;
   datetime       endTime;
   int            endBar;
   double         slope;         // Price change per bar
   int            touchCount;
   bool           broken;
   int            direction;     // +1 = uptrend (connecting lows), -1 = downtrend (connecting highs)
   datetime       breakTime;
};


struct EntryZone
{
   int            id;
   //--- Sweep origin
   int            sweepBar;
   datetime       sweepTime;
   double         sweepPrice;
   double         levelPrice;
   ENUM_SWEEP_DIR direction;
   ENUM_SWEEP_CONTEXT context;
   //--- Displacement
   int            displacementBar;
   datetime       displacementTime;
   double         displacementClose;
   //--- Order Block
   int            obBar;
   double         obHigh;
   double         obLow;
   datetime       obTime;
   //--- Entry levels
   double         entryPrice;
   double         slPrice;
   double         tpPrice;
   ENUM_TP_TYPE   tpType;
   string         tpTargetLabel;
   double         riskReward;
   //--- Lifecycle
   ENUM_ZONE_STATUS status;
   datetime       statusChangeTime;
   datetime       creationTime;
   int            creationBar;
   bool           approachAlertFired;
   bool           triggerAlertFired;
   bool           resultAlertFired;
   //--- Confluence
   bool           onTrendline;
   int            trendlineTouches;
   int            confidenceScore;
};

//+------------------------------------------------------------------+
//| Input parameters                                                   |
//+------------------------------------------------------------------+
//--- Detection
input group "=== Detection ==="
input int      InpSwingStrength      = 5;       // Swing strength (bars each side)
input int      InpHTFSwingStrength   = 10;      // HTF extreme swing strength
input int      InpMaxBars            = 500;     // Max bars to analyze
input double   InpDisplacementRatio  = 0.7;     // Min body/range for displacement
input int      InpATRPeriod          = 14;      // ATR period
input double   InpEqualTolerance     = 0.3;     // Equal level tolerance (x ATR)
input int      InpMaxBarsAfterSweep  = 20;      // Window to find displacement after sweep
input int      InpMinEqualTouches    = 2;       // Min touches for equal level

//--- Trendlines
input group "=== Trendlines ==="
input int      InpMinTrendlineTouches = 2;      // Min touches for valid trendline
input double   InpTrendlineTouchTol  = 0.1;     // Touch tolerance (x ATR)
input int      InpMaxTrendlines      = 4;       // Max active trendlines

//--- Entry Zones
input group "=== Entry Zones ==="
input double   InpSLBufferATR        = 0.15;    // SL buffer beyond OB (x ATR)
input double   InpFallbackRR         = 2.0;     // Fallback risk:reward if no liquidity TP
input double   InpApproachDistATR    = 0.5;     // Approach alert distance (x ATR)
input int      InpZoneExtensionBars  = 50;      // Zone forward extension (bars)
input int      InpMaxActiveZones     = 5;       // Max active entry zones
input int      InpMaxZoneAgeBars     = 200;     // Max zone age before invalidation

//--- Alerts
input group "=== Alerts ==="
input bool     InpAlertPopup         = true;    // Alert popup
input bool     InpAlertSound         = true;    // Alert sound
input bool     InpAlertPush          = false;   // Push notification
input bool     InpAlertOnApproach    = true;    // Alert when price approaches zone
input bool     InpAlertOnTrigger     = true;    // Alert when zone triggered
input bool     InpAlertOnResult      = true;    // Alert on TP/SL hit

//--- Visual
input group "=== Visual ==="
input bool     InpShowZones          = true;    // Show entry zones
input bool     InpShowSLTP           = true;    // Show SL/TP lines
input bool     InpShowTargets        = true;    // Show TP target labels
input bool     InpShowDashboard      = true;    // Show dashboard
input bool     InpShowStructure      = true;    // Show sweep arrows
input bool     InpShowLiquidity      = true;    // Show equal level lines
input bool     InpShowTrendlines     = true;    // Show trendlines

//--- Colors
input group "=== Colors ==="
input color    InpDemandColor        = clrDodgerBlue;  // Demand zone (bullish OB)
input color    InpSupplyColor        = clrCrimson;      // Supply zone (bearish OB)
input color    InpEntryColor         = clrWhite;        // Entry line
input color    InpSLColor            = clrRed;          // Stop loss line
input color    InpTPColor            = clrLime;         // Take profit line
input color    InpApproachColor      = clrGold;         // Approaching zone
input color    InpTriggeredColor     = clrLime;         // Triggered zone
input color    InpInvalidColor       = clrDimGray;      // Invalidated zone
input color    InpLiqTargetColor     = clrMagenta;      // Liquidity target
input color    InpTrendUpColor       = clrDodgerBlue;   // Uptrend trendline
input color    InpTrendDownColor     = clrCrimson;      // Downtrend trendline
input color    InpTrendBrokenColor   = clrDimGray;      // Broken trendline
input color    InpSweepArrowColor    = clrGold;         // Sweep arrow
input color    InpEqualHighColor     = clrOrangeRed;    // Equal highs
input color    InpEqualLowColor      = clrDodgerBlue;   // Equal lows
input int      InpFontSize           = 8;               // Label font size

//--- Wave Projection (manual - draw trendline "Wave01" to project waves)
input group "=== Wave Projection ==="
input string   InpWaveTrendline      = "Wave01";       // Trendline name for Wave 1
input int      InpWaveSpacingMinutes = 60;             // Future wave spacing (minutes)
input color    InpWave1Color         = clrBlue;        // Wave 1 color
input color    InpWave2Color         = clrRed;         // Wave 2 color
input color    InpWave3Color         = clrGreen;       // Wave 3 color
input color    InpWave4Color         = clrOrange;      // Wave 4 color
input color    InpWave5Color         = clrYellow;      // Wave 5 color
input color    InpWaveLabelColor     = clrWhite;       // Wave label color
input color    InpFiboColor          = clrMagenta;     // Fibonacci color
input bool     InpFiboReversed       = false;          // Reverse Fibonacci direction

//+------------------------------------------------------------------+
//| Global variables                                                   |
//+------------------------------------------------------------------+
//--- Detection arrays (reset each bar)
SwingPoint       g_swingHighs[];
SwingPoint       g_swingLows[];
int              g_swingHighCount = 0;
int              g_swingLowCount  = 0;

SwingPoint       g_htfSwingHighs[];
SwingPoint       g_htfSwingLows[];
int              g_htfSwingHighCount = 0;
int              g_htfSwingLowCount  = 0;

EqualLevel       g_equalLevels[];
int              g_equalLevelCount = 0;

//--- Persistent state (survives across bars)
EntryZone        g_zones[];
int              g_zoneCount = 0;
int              g_nextZoneId = 1;

TrendLine        g_trendlines[];
int              g_trendlineCount = 0;

//--- Stats
int              g_tpCount = 0;
int              g_slCount = 0;
int              g_invalidCount = 0;

//--- Misc
string           g_objPrefix = "SNP_";
int              g_lastCalculatedBars = 0;
double           g_atrValue = 0;
string           g_wavePrefix = "WV_";

//+------------------------------------------------------------------+
//| Custom indicator initialization                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("SniperEntry v1.0 initializing...");
   Print("Swing: ", InpSwingStrength, " | HTF: ", InpHTFSwingStrength,
         " | Displacement: ", DoubleToString(InpDisplacementRatio, 1),
         " | ATR: ", InpATRPeriod, " | MaxZones: ", InpMaxActiveZones);

   CleanAllObjects();
   ClearWaveObjects();
   Comment("");

   EventSetTimer(5); // Check for wave trendline every 5 seconds

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ClearWaveObjects();
   CleanAllObjects();
   Comment("");
   Print("SniperEntry deinitialized");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration                                         |
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
   //--- Only recalculate on new bar or first run
   if(rates_total == g_lastCalculatedBars && prev_calculated > 0)
      return rates_total;

   g_lastCalculatedBars = rates_total;

   //--- Need enough bars
   if(rates_total < InpATRPeriod + InpHTFSwingStrength + 10)
      return rates_total;

   //--- Set arrays as series (index 0 = current bar)
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(close, true);

   //--- Determine analysis range
   int barsToAnalyze = MathMin(InpMaxBars, rates_total);
   int startBar = barsToAnalyze - 1;

   //--- Clean drawing objects (redraw each bar)
   CleanAllObjects();

   //--- Reset detection arrays (NOT zones/trendlines - those persist)
   ResetDetectionArrays();

   //--- 1. Calculate ATR
   g_atrValue = CalculateATR(high, low, close, InpATRPeriod, barsToAnalyze);
   if(g_atrValue <= 0) g_atrValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100;

   //--- 2. Detect swing points (normal + HTF)
   DetectSwingPoints(high, low, time, startBar, InpSwingStrength,
                     g_swingHighs, g_swingHighCount,
                     g_swingLows, g_swingLowCount);

   DetectSwingPoints(high, low, time, startBar, InpHTFSwingStrength,
                     g_htfSwingHighs, g_htfSwingHighCount,
                     g_htfSwingLows, g_htfSwingLowCount);

   //--- 3. Detect equal levels (for sweep detection AND TP targeting)
   DetectEqualLevels(high, low, close, time, startBar);

   //--- 4. Build trendlines from swing wicks
   if(InpShowTrendlines)
      BuildTrendlines(high, low, time, startBar);

   //--- 5. Detect sweeps and create new zones
   SweepEvent localSweeps[];
   int localSweepCount = 0;
   DetectSweeps(high, low, close, time, startBar, localSweeps, localSweepCount);
   ClassifySweepContext(localSweeps, localSweepCount);

   //--- 6. For each new sweep, run pipeline and create entry zones
   for(int i = 0; i < localSweepCount; i++)
   {
      //--- Skip if zone already exists for this sweep
      if(IsZoneAlreadyCreated(localSweeps[i].bar, localSweeps[i].levelPrice))
         continue;

      //--- Step 1: Check structure held (no CHoCH)
      if(!CheckPostSweepStructure(localSweeps[i], high, low, close, time, startBar))
         continue;

      //--- Step 2: Detect displacement
      int dispBar = -1;
      datetime dispTime = 0;
      double dispClose = 0;
      if(!DetectDisplacement(localSweeps[i], open, high, low, close, time, startBar,
                             dispBar, dispTime, dispClose))
         continue;

      //--- Step 3: Identify order block
      int obBar = -1;
      double obHi = 0, obLo = 0;
      datetime obTime = 0;
      if(!IdentifyOrderBlock(localSweeps[i], dispBar, open, high, low, close, time, startBar,
                             obBar, obHi, obLo, obTime))
         continue;

      //--- Check trendline confluence
      bool onTL = false;
      int tlTouches = 0;
      CheckTrendlineConfluence(localSweeps[i].direction, obHi, obLo, time, startBar,
                               onTL, tlTouches);

      //--- Create the entry zone
      CreateEntryZone(localSweeps[i], dispBar, dispTime, dispClose,
                      obBar, obHi, obLo, obTime,
                      onTL, tlTouches,
                      high, low, close, time, startBar);
   }

   //--- 7. Update zone statuses (approach, trigger, TP, SL, invalidation)
   UpdateAllZoneStatuses(high, low, close, time, rates_total);

   //--- 8. Update trendline status (check breaks)
   UpdateTrendlineStatus(high, low, close, time, startBar);

   //--- 9. Enforce max zones
   EnforceMaxZones();

   //--- 10. Alerts
   CheckApproachAlerts();
   CheckTriggerAlerts();
   CheckResultAlerts();

   //--- 11. Draw everything
   DrawAllZones(time, high, low, rates_total);
   if(InpShowLiquidity)
      DrawEqualLevels(time, rates_total);
   if(InpShowTrendlines)
      DrawTrendlines(time, rates_total);

   //--- 12. Dashboard
   if(InpShowDashboard)
      BuildDashboard();

   ChartRedraw(0);

   return rates_total;
}

//+------------------------------------------------------------------+
//| Reset detection arrays (NOT persistent state)                      |
//+------------------------------------------------------------------+
void ResetDetectionArrays()
{
   g_swingHighCount    = 0;
   g_swingLowCount     = 0;
   g_htfSwingHighCount = 0;
   g_htfSwingLowCount  = 0;
   g_equalLevelCount   = 0;

   ArrayResize(g_swingHighs, 0);
   ArrayResize(g_swingLows, 0);
   ArrayResize(g_htfSwingHighs, 0);
   ArrayResize(g_htfSwingLows, 0);
   ArrayResize(g_equalLevels, 0);
}

//+------------------------------------------------------------------+
//| Clean all indicator objects                                        |
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
      //--- Swing high
      bool isSwingHigh = true;
      for(int j = 1; j <= strength; j++)
      {
         if(high[i] <= high[i + j] || high[i] <= high[i - j])
         { isSwingHigh = false; break; }
      }

      if(isSwingHigh)
      {
         int idx = highCount++;
         ArrayResize(swingHighs, highCount);
         swingHighs[idx].bar    = i;
         swingHighs[idx].price  = high[i];
         swingHighs[idx].isHigh = true;
         swingHighs[idx].time   = time[i];
      }

      //--- Swing low
      bool isSwingLow = true;
      for(int j = 1; j <= strength; j++)
      {
         if(low[i] >= low[i + j] || low[i] >= low[i - j])
         { isSwingLow = false; break; }
      }

      if(isSwingLow)
      {
         int idx = lowCount++;
         ArrayResize(swingLows, lowCount);
         swingLows[idx].bar    = i;
         swingLows[idx].price  = low[i];
         swingLows[idx].isHigh = false;
         swingLows[idx].time   = time[i];
      }
   }
}

//+------------------------------------------------------------------+
//| Detect equal highs and lows from ALL bar wicks                     |
//+------------------------------------------------------------------+
void DetectEqualLevels(const double &high[], const double &low[],
                       const double &close[], const datetime &time[],
                       int maxBar)
{
   g_equalLevelCount = 0;
   double tolerance = g_atrValue * InpEqualTolerance;
   double sweepTol  = g_atrValue * 0.05;
   int minBarGap = 3;

   //--- Equal highs
   {
      bool used[];
      ArrayResize(used, maxBar + 1);
      ArrayInitialize(used, false);

      for(int i = maxBar; i >= 0; i--)
      {
         if(used[i]) continue;

         double levelPrice = high[i];
         int touches = 1;
         int oldestBar = i, newestBar = i;
         datetime oldestTime = time[i], newestTime = time[i];
         int lastTouchBar = i;

         for(int j = i - 1; j >= 0; j--)
         {
            if(used[j]) continue;
            if(MathAbs(high[j] - levelPrice) <= tolerance)
            {
               if(MathAbs(j - lastTouchBar) >= minBarGap)
               {
                  touches++;
                  used[j] = true;
                  levelPrice = ((levelPrice * (touches - 1)) + high[j]) / touches;
                  lastTouchBar = j;
                  if(j > oldestBar) { oldestBar = j; oldestTime = time[j]; }
                  if(j < newestBar) { newestBar = j; newestTime = time[j]; }
               }
            }
         }

         if(touches >= InpMinEqualTouches)
         {
            used[i] = true;
            int idx = g_equalLevelCount++;
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

            for(int b = newestBar - 1; b >= 0; b--)
            {
               if(high[b] > levelPrice + sweepTol && close[b] < levelPrice)
               { g_equalLevels[idx].swept = true; g_equalLevels[idx].sweepBar = b; g_equalLevels[idx].sweepTime = time[b]; break; }
               if(close[b] > levelPrice + sweepTol)
               { g_equalLevels[idx].swept = true; g_equalLevels[idx].sweepBar = b; g_equalLevels[idx].sweepTime = time[b]; break; }
            }
         }
      }
   }

   //--- Equal lows
   {
      bool used[];
      ArrayResize(used, maxBar + 1);
      ArrayInitialize(used, false);

      for(int i = maxBar; i >= 0; i--)
      {
         if(used[i]) continue;

         double levelPrice = low[i];
         int touches = 1;
         int oldestBar = i, newestBar = i;
         datetime oldestTime = time[i], newestTime = time[i];
         int lastTouchBar = i;

         for(int j = i - 1; j >= 0; j--)
         {
            if(used[j]) continue;
            if(MathAbs(low[j] - levelPrice) <= tolerance)
            {
               if(MathAbs(j - lastTouchBar) >= minBarGap)
               {
                  touches++;
                  used[j] = true;
                  levelPrice = ((levelPrice * (touches - 1)) + low[j]) / touches;
                  lastTouchBar = j;
                  if(j > oldestBar) { oldestBar = j; oldestTime = time[j]; }
                  if(j < newestBar) { newestBar = j; newestTime = time[j]; }
               }
            }
         }

         if(touches >= InpMinEqualTouches)
         {
            used[i] = true;
            int idx = g_equalLevelCount++;
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

            for(int b = newestBar - 1; b >= 0; b--)
            {
               if(low[b] < levelPrice - sweepTol && close[b] > levelPrice)
               { g_equalLevels[idx].swept = true; g_equalLevels[idx].sweepBar = b; g_equalLevels[idx].sweepTime = time[b]; break; }
               if(close[b] < levelPrice - sweepTol)
               { g_equalLevels[idx].swept = true; g_equalLevels[idx].sweepBar = b; g_equalLevels[idx].sweepTime = time[b]; break; }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Detect sweeps (returns local array, not global)                    |
//+------------------------------------------------------------------+
void DetectSweeps(const double &high[], const double &low[],
                  const double &close[], const datetime &time[],
                  int maxBar,
                  SweepEvent &sweeps[], int &sweepCount)
{
   sweepCount = 0;
   double tolerance = g_atrValue * (InpEqualTolerance / 100.0);
   double sweepTol  = g_atrValue * 0.05;
   double dedupPrice = g_atrValue * 0.2;

   //--- Cluster swing highs
   double eqHighPrices[];
   int    eqHighBars[];
   int    eqHighCount = 0;
   ClusterSwingLevels(g_swingHighs, g_swingHighCount, tolerance,
                      eqHighPrices, eqHighBars, eqHighCount);

   //--- Cluster swing lows
   double eqLowPrices[];
   int    eqLowBars[];
   int    eqLowCount = 0;
   ClusterSwingLevels(g_swingLows, g_swingLowCount, tolerance,
                      eqLowPrices, eqLowBars, eqLowCount);

   //--- Add standalone swings
   AddStandaloneSwings(g_swingHighs, g_swingHighCount, eqHighPrices, eqHighBars, eqHighCount, tolerance);
   AddStandaloneSwings(g_swingLows, g_swingLowCount, eqLowPrices, eqLowBars, eqLowCount, tolerance);

   //--- Scan for sweeps of equal highs (bearish)
   for(int i = 0; i < eqHighCount; i++)
   {
      int scanStart = eqHighBars[i] - 1;
      if(scanStart < 0) scanStart = 0;

      for(int b = scanStart; b >= 0; b--)
      {
         if(high[b] > eqHighPrices[i] + sweepTol && close[b] < eqHighPrices[i])
         {
            if(!IsDuplicateSweepLocal(sweeps, sweepCount, b, eqHighPrices[i], dedupPrice))
            {
               int idx = sweepCount++;
               ArrayResize(sweeps, sweepCount);
               ZeroMemory(sweeps[idx]);
               sweeps[idx].bar        = b;
               sweeps[idx].time       = time[b];
               sweeps[idx].levelPrice = eqHighPrices[i];
               sweeps[idx].sweepPrice = high[b];
               sweeps[idx].direction  = SWEEP_BEARISH;
               sweeps[idx].context    = CTX_UNKNOWN;
               sweeps[idx].displacementBar = -1;
               sweeps[idx].obStartBar = -1;
            }
            break;
         }
      }
   }

   //--- Scan for sweeps of equal lows (bullish)
   for(int i = 0; i < eqLowCount; i++)
   {
      int scanStart = eqLowBars[i] - 1;
      if(scanStart < 0) scanStart = 0;

      for(int b = scanStart; b >= 0; b--)
      {
         if(low[b] < eqLowPrices[i] - sweepTol && close[b] > eqLowPrices[i])
         {
            if(!IsDuplicateSweepLocal(sweeps, sweepCount, b, eqLowPrices[i], dedupPrice))
            {
               int idx = sweepCount++;
               ArrayResize(sweeps, sweepCount);
               ZeroMemory(sweeps[idx]);
               sweeps[idx].bar        = b;
               sweeps[idx].time       = time[b];
               sweeps[idx].levelPrice = eqLowPrices[i];
               sweeps[idx].sweepPrice = low[b];
               sweeps[idx].direction  = SWEEP_BULLISH;
               sweeps[idx].context    = CTX_UNKNOWN;
               sweeps[idx].displacementBar = -1;
               sweeps[idx].obStartBar = -1;
            }
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cluster swing points into equal levels                             |
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
         int idx = outCount++;
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
      bool alreadyClustered = false;
      for(int j = 0; j < outCount; j++)
      {
         if(MathAbs(swings[i].price - prices[j]) <= tolerance * 2)
         { alreadyClustered = true; break; }
      }

      if(!alreadyClustered)
      {
         int idx = outCount++;
         ArrayResize(prices, outCount);
         ArrayResize(bars, outCount);
         prices[idx] = swings[i].price;
         bars[idx]   = swings[i].bar;
      }
   }
}

//+------------------------------------------------------------------+
//| Local sweep deduplication                                          |
//+------------------------------------------------------------------+
bool IsDuplicateSweepLocal(const SweepEvent &sweeps[], int count,
                           int bar, double price, double priceTol)
{
   for(int i = 0; i < count; i++)
   {
      if(MathAbs(sweeps[i].bar - bar) <= 3 &&
         MathAbs(sweeps[i].levelPrice - price) <= priceTol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Classify sweep context                                             |
//+------------------------------------------------------------------+
void ClassifySweepContext(SweepEvent &sweeps[], int count)
{
   for(int i = 0; i < count; i++)
   {
      bool isHTFExtreme = IsNearHTFExtreme(sweeps[i].levelPrice);
      bool isInRange    = IsWithinRange(sweeps[i].bar, sweeps[i].levelPrice);

      if(isHTFExtreme)
         sweeps[i].context = CTX_HTF_EXTREME;
      else if(isInRange)
         sweeps[i].context = CTX_RANGE_SWEEP;
      else
         sweeps[i].context = CTX_UNKNOWN;
   }
}

//+------------------------------------------------------------------+
//| Check if price is within a consolidation range                     |
//+------------------------------------------------------------------+
bool IsWithinRange(int sweepBar, double sweepPrice)
{
   int lookback = 50;
   int rangeStart = sweepBar + lookback;
   int rangeEnd   = sweepBar;

   double localHigh = -999999;
   double localLow  = 999999;
   int    highCount = 0, lowCount = 0;

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

   return (sweepPrice >= localLow - g_atrValue * 0.5 &&
           sweepPrice <= localHigh + g_atrValue * 0.5);
}

//+------------------------------------------------------------------+
//| Check if price is near an HTF extreme                              |
//+------------------------------------------------------------------+
bool IsNearHTFExtreme(double sweepPrice)
{
   double htfTol = g_atrValue * 0.5;
   for(int i = 0; i < g_htfSwingHighCount; i++)
      if(MathAbs(sweepPrice - g_htfSwingHighs[i].price) <= htfTol) return true;
   for(int i = 0; i < g_htfSwingLowCount; i++)
      if(MathAbs(sweepPrice - g_htfSwingLows[i].price) <= htfTol) return true;
   return false;
}

//+------------------------------------------------------------------+
//| Step 1: Check post-sweep structure (returns true if held)          |
//+------------------------------------------------------------------+
bool CheckPostSweepStructure(const SweepEvent &sw,
                              const double &high[], const double &low[],
                              const double &close[], const datetime &time[],
                              int maxBar)
{
   int sweepBar = sw.bar;
   int scanEnd  = MathMax(sweepBar - InpMaxBarsAfterSweep, 0);

   double recentSwingLow  = 999999;
   double recentSwingHigh = 0;

   for(int i = 0; i < g_swingLowCount; i++)
   {
      if(g_swingLows[i].bar > sweepBar && g_swingLows[i].bar <= sweepBar + 30)
         if(recentSwingLow > g_swingLows[i].price)
            recentSwingLow = g_swingLows[i].price;
   }

   for(int i = 0; i < g_swingHighCount; i++)
   {
      if(g_swingHighs[i].bar > sweepBar && g_swingHighs[i].bar <= sweepBar + 30)
         if(recentSwingHigh < g_swingHighs[i].price)
            recentSwingHigh = g_swingHighs[i].price;
   }

   if(sw.direction == SWEEP_BULLISH)
   {
      if(recentSwingLow < 999999)
      {
         for(int b = sweepBar - 1; b >= scanEnd; b--)
            if(close[b] < recentSwingLow) return false; // CHoCH
      }
   }
   else
   {
      if(recentSwingHigh > 0)
      {
         for(int b = sweepBar - 1; b >= scanEnd; b--)
            if(close[b] > recentSwingHigh) return false; // CHoCH
      }
   }

   return true; // Structure held
}

//+------------------------------------------------------------------+
//| Step 2: Detect displacement (returns true + out-params)            |
//+------------------------------------------------------------------+
bool DetectDisplacement(const SweepEvent &sw,
                        const double &open[], const double &high[],
                        const double &low[], const double &close[],
                        const datetime &time[], int maxBar,
                        int &outBar, datetime &outTime, double &outClose)
{
   int sweepBar = sw.bar;
   int scanEnd  = MathMax(sweepBar - InpMaxBarsAfterSweep, 0);

   for(int b = sweepBar - 1; b >= scanEnd; b--)
   {
      double range = high[b] - low[b];
      if(range <= 0) continue;

      double body = MathAbs(close[b] - open[b]);
      if(body / range < InpDisplacementRatio) continue;

      bool isBull = (close[b] > open[b]);
      bool isBear = (close[b] < open[b]);

      if(sw.direction == SWEEP_BULLISH && !isBull) continue;
      if(sw.direction == SWEEP_BEARISH && !isBear) continue;

      double threshold = g_atrValue * 0.3;
      if(sw.direction == SWEEP_BULLISH && close[b] < sw.levelPrice + threshold) continue;
      if(sw.direction == SWEEP_BEARISH && close[b] > sw.levelPrice - threshold) continue;

      outBar   = b;
      outTime  = time[b];
      outClose = close[b];
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Step 3: Identify order block (returns true + out-params)           |
//+------------------------------------------------------------------+
bool IdentifyOrderBlock(const SweepEvent &sw, int dispBar,
                        const double &open[], const double &high[],
                        const double &low[], const double &close[],
                        const datetime &time[], int maxBar,
                        int &outBar, double &outHigh, double &outLow,
                        datetime &outTime)
{
   if(dispBar < 0) return false;
   int maxLookback = 5;

   for(int b = dispBar + 1; b <= MathMin(dispBar + maxLookback, maxBar); b++)
   {
      bool isBullCandle = (close[b] > open[b]);
      bool isBearCandle = (close[b] < open[b]);
      double body = MathAbs(close[b] - open[b]);
      double range = high[b] - low[b];
      bool isSmallBody = (range > 0 && body / range < 0.3);

      bool isOB = false;
      if(sw.direction == SWEEP_BULLISH && (isBearCandle || isSmallBody)) isOB = true;
      if(sw.direction == SWEEP_BEARISH && (isBullCandle || isSmallBody)) isOB = true;

      if(isOB)
      {
         outBar  = b;
         outHigh = high[b];
         outLow  = low[b];
         outTime = time[b];
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check if a zone already exists for this sweep                      |
//+------------------------------------------------------------------+
bool IsZoneAlreadyCreated(int sweepBar, double levelPrice)
{
   double priceTol = g_atrValue * 0.2;
   for(int i = 0; i < g_zoneCount; i++)
   {
      if(MathAbs(g_zones[i].sweepBar - sweepBar) <= 3 &&
         MathAbs(g_zones[i].levelPrice - levelPrice) <= priceTol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| PLACEHOLDER - remaining functions implemented in next phases       |
//+------------------------------------------------------------------+

// Forward declarations for functions to be implemented:

void BuildTrendlines(const double &high[], const double &low[],
                     const datetime &time[], int maxBar)
{
   // Phase 5 - Trendline detection
   g_trendlineCount = 0;
   ArrayResize(g_trendlines, 0);

   //--- Build uptrend lines from swing lows (wick-to-wick)
   if(g_swingLowCount >= InpMinTrendlineTouches)
   {
      for(int i = 0; i < g_swingLowCount - 1 && g_trendlineCount < InpMaxTrendlines; i++)
      {
         //--- Try connecting this swing low to subsequent ones
         double startP = g_swingLows[i].price;
         int    startB = g_swingLows[i].bar;
         datetime startT = g_swingLows[i].time;

         for(int j = i + 1; j < g_swingLowCount; j++)
         {
            //--- Must be more recent (lower bar index in series)
            if(g_swingLows[j].bar >= startB) continue;

            double endP = g_swingLows[j].price;
            int    endB = g_swingLows[j].bar;
            datetime endT = g_swingLows[j].time;

            //--- Uptrend: price should be rising or flat
            if(endP < startP - g_atrValue * 0.2) continue;

            //--- Calculate slope (price per bar)
            int barDiff = startB - endB;
            if(barDiff <= 0) continue;
            double slope = (endP - startP) / barDiff;

            //--- Count touches along this line
            int touches = 2; // Start and end are touches
            double touchTol = g_atrValue * InpTrendlineTouchTol;

            //--- Check intermediate swings
            for(int k = 0; k < g_swingLowCount; k++)
            {
               if(k == i || k == j) continue;
               int kBar = g_swingLows[k].bar;
               if(kBar >= startB || kBar <= endB) continue;

               double projectedPrice = startP + slope * (startB - kBar);
               if(MathAbs(g_swingLows[k].price - projectedPrice) <= touchTol)
                  touches++;
            }

            if(touches >= InpMinTrendlineTouches)
            {
               //--- Check no bar closes below the line (invalid if broken)
               bool broken = false;
               datetime breakT = 0;
               for(int b = startB - 1; b >= 0; b--)
               {
                  double projP = startP + slope * (startB - b);
                  if(low[b] < projP - touchTol * 2)
                  {
                     // Check if close is below - that's a break
                     // Just wick below is a touch, not a break
                  }
                  // A close below the projected line = break
                  // But we only check bars AFTER the last defined point
                  if(b < endB)
                  {
                     double projAtB = startP + slope * (startB - b);
                     if(low[b] < projAtB - touchTol * 3) // Wick clearly below
                     {
                        broken = true;
                        breakT = time[b];
                        break;
                     }
                  }
               }

               int idx = g_trendlineCount++;
               ArrayResize(g_trendlines, g_trendlineCount);
               g_trendlines[idx].startPrice  = startP;
               g_trendlines[idx].startTime   = startT;
               g_trendlines[idx].startBar    = startB;
               g_trendlines[idx].endPrice    = endP;
               g_trendlines[idx].endTime     = endT;
               g_trendlines[idx].endBar      = endB;
               g_trendlines[idx].slope       = slope;
               g_trendlines[idx].touchCount  = touches;
               g_trendlines[idx].broken      = broken;
               g_trendlines[idx].direction   = 1; // Uptrend
               g_trendlines[idx].breakTime   = breakT;
            }

            break; // Only try nearest valid connection per start point
         }
      }
   }

   //--- Build downtrend lines from swing highs (wick-to-wick)
   if(g_swingHighCount >= InpMinTrendlineTouches)
   {
      for(int i = 0; i < g_swingHighCount - 1 && g_trendlineCount < InpMaxTrendlines; i++)
      {
         double startP = g_swingHighs[i].price;
         int    startB = g_swingHighs[i].bar;
         datetime startT = g_swingHighs[i].time;

         for(int j = i + 1; j < g_swingHighCount; j++)
         {
            if(g_swingHighs[j].bar >= startB) continue;

            double endP = g_swingHighs[j].price;
            int    endB = g_swingHighs[j].bar;
            datetime endT = g_swingHighs[j].time;

            //--- Downtrend: price should be falling or flat
            if(endP > startP + g_atrValue * 0.2) continue;

            int barDiff = startB - endB;
            if(barDiff <= 0) continue;
            double slope = (endP - startP) / barDiff;

            int touches = 2;
            double touchTol = g_atrValue * InpTrendlineTouchTol;

            for(int k = 0; k < g_swingHighCount; k++)
            {
               if(k == i || k == j) continue;
               int kBar = g_swingHighs[k].bar;
               if(kBar >= startB || kBar <= endB) continue;

               double projectedPrice = startP + slope * (startB - kBar);
               if(MathAbs(g_swingHighs[k].price - projectedPrice) <= touchTol)
                  touches++;
            }

            if(touches >= InpMinTrendlineTouches)
            {
               bool broken = false;
               datetime breakT = 0;
               for(int b = endB - 1; b >= 0; b--)
               {
                  double projAtB = startP + slope * (startB - b);
                  if(high[b] > projAtB + touchTol * 3)
                  {
                     broken = true;
                     breakT = time[b];
                     break;
                  }
               }

               int idx = g_trendlineCount++;
               ArrayResize(g_trendlines, g_trendlineCount);
               g_trendlines[idx].startPrice  = startP;
               g_trendlines[idx].startTime   = startT;
               g_trendlines[idx].startBar    = startB;
               g_trendlines[idx].endPrice    = endP;
               g_trendlines[idx].endTime     = endT;
               g_trendlines[idx].endBar      = endB;
               g_trendlines[idx].slope       = slope;
               g_trendlines[idx].touchCount  = touches;
               g_trendlines[idx].broken      = broken;
               g_trendlines[idx].direction   = -1; // Downtrend
               g_trendlines[idx].breakTime   = breakT;
            }

            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Project trendline price at a given bar                             |
//+------------------------------------------------------------------+
double ProjectTrendlinePrice(const TrendLine &tl, int bar)
{
   return tl.startPrice + tl.slope * (tl.startBar - bar);
}

//+------------------------------------------------------------------+
//| Check trendline confluence for an OB zone                          |
//+------------------------------------------------------------------+
void CheckTrendlineConfluence(ENUM_SWEEP_DIR dir, double obHigh, double obLow,
                              const datetime &time[], int maxBar,
                              bool &onTL, int &tlTouches)
{
   onTL = false;
   tlTouches = 0;
   double touchTol = g_atrValue * InpTrendlineTouchTol * 2;

   for(int i = 0; i < g_trendlineCount; i++)
   {
      if(g_trendlines[i].broken) continue;

      //--- For bullish entry, check uptrend lines near OB low
      //--- For bearish entry, check downtrend lines near OB high
      double checkPrice = (dir == SWEEP_BULLISH) ? obLow : obHigh;

      //--- Project trendline to the OB bar area
      int obBar = 0; // Current area - use most recent projection
      for(int b = 5; b >= 0; b--)
      {
         double projP = ProjectTrendlinePrice(g_trendlines[i], b);
         if(MathAbs(checkPrice - projP) <= touchTol)
         {
            //--- Direction alignment: uptrend TL for bullish, downtrend for bearish
            if((dir == SWEEP_BULLISH && g_trendlines[i].direction == 1) ||
               (dir == SWEEP_BEARISH && g_trendlines[i].direction == -1))
            {
               onTL = true;
               tlTouches = g_trendlines[i].touchCount;
               return;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Find opposing liquidity for TP targeting                           |
//+------------------------------------------------------------------+
double FindOpposingLiquidity(ENUM_SWEEP_DIR dir, double entryPrice, double slPrice,
                              string &tpLabel, ENUM_TP_TYPE &tpType)
{
   double bestTP = 0;
   double bestDist = 999999;
   tpLabel = "";
   tpType = TP_FALLBACK_RR;

   double riskDist = MathAbs(entryPrice - slPrice);
   if(riskDist <= 0) riskDist = g_atrValue;

   //--- Scan equal levels for opposing unswept liquidity
   for(int i = 0; i < g_equalLevelCount; i++)
   {
      if(g_equalLevels[i].swept) continue;

      if(dir == SWEEP_BULLISH)
      {
         //--- Bullish: TP at equal highs above entry
         if(!g_equalLevels[i].isHigh) continue;
         if(g_equalLevels[i].price <= entryPrice) continue;

         double dist = g_equalLevels[i].price - entryPrice;
         double rr = dist / riskDist;
         if(rr < 1.0) continue; // Need at least 1:1

         if(dist < bestDist)
         {
            bestDist = dist;
            bestTP = g_equalLevels[i].price;
            tpLabel = "EQH x" + IntegerToString(g_equalLevels[i].touches) +
                     " @ " + DoubleToString(g_equalLevels[i].price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
            tpType = TP_LIQUIDITY;
         }
      }
      else
      {
         //--- Bearish: TP at equal lows below entry
         if(g_equalLevels[i].isHigh) continue;
         if(g_equalLevels[i].price >= entryPrice) continue;

         double dist = entryPrice - g_equalLevels[i].price;
         double rr = dist / riskDist;
         if(rr < 1.0) continue;

         if(dist < bestDist)
         {
            bestDist = dist;
            bestTP = g_equalLevels[i].price;
            tpLabel = "EQL x" + IntegerToString(g_equalLevels[i].touches) +
                     " @ " + DoubleToString(g_equalLevels[i].price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
            tpType = TP_LIQUIDITY;
         }
      }
   }

   //--- If no liquidity target, try swing points
   if(bestTP == 0)
   {
      if(dir == SWEEP_BULLISH)
      {
         for(int i = 0; i < g_swingHighCount; i++)
         {
            if(g_swingHighs[i].price <= entryPrice) continue;
            double dist = g_swingHighs[i].price - entryPrice;
            double rr = dist / riskDist;
            if(rr < 1.0) continue;
            if(dist < bestDist)
            {
               bestDist = dist;
               bestTP = g_swingHighs[i].price;
               tpLabel = "Swing High";
               tpType = TP_LIQUIDITY;
            }
         }
      }
      else
      {
         for(int i = 0; i < g_swingLowCount; i++)
         {
            if(g_swingLows[i].price >= entryPrice) continue;
            double dist = entryPrice - g_swingLows[i].price;
            double rr = dist / riskDist;
            if(rr < 1.0) continue;
            if(dist < bestDist)
            {
               bestDist = dist;
               bestTP = g_swingLows[i].price;
               tpLabel = "Swing Low";
               tpType = TP_LIQUIDITY;
            }
         }
      }
   }

   //--- Fallback: fixed RR
   if(bestTP == 0)
   {
      if(dir == SWEEP_BULLISH)
         bestTP = entryPrice + riskDist * InpFallbackRR;
      else
         bestTP = entryPrice - riskDist * InpFallbackRR;

      tpLabel = "1:" + DoubleToString(InpFallbackRR, 1) + " RR";
      tpType = TP_FALLBACK_RR;
   }

   return bestTP;
}

//+------------------------------------------------------------------+
//| Calculate confluence score                                         |
//+------------------------------------------------------------------+
int CalculateConfluenceScore(ENUM_SWEEP_CONTEXT ctx, bool onTL, int tlTouches)
{
   int score = 1; // Base: OB after sweep + displacement

   score += 1; // Structure held (always true if we got here)

   if(ctx == CTX_RANGE_SWEEP) score += 1; // Range context (fuel)

   if(onTL) score += 1; // On trendline

   return score;
}

//+------------------------------------------------------------------+
//| Create entry zone with entry/SL/TP                                 |
//+------------------------------------------------------------------+
void CreateEntryZone(const SweepEvent &sw,
                     int dispBar, datetime dispTime, double dispClose,
                     int obBar, double obHi, double obLo, datetime obTime,
                     bool onTL, int tlTouches,
                     const double &high[], const double &low[],
                     const double &close[], const datetime &time[],
                     int maxBar)
{
   //--- Check max zones
   int activeCount = 0;
   for(int i = 0; i < g_zoneCount; i++)
   {
      if(g_zones[i].status == ZONE_PENDING || g_zones[i].status == ZONE_APPROACHING)
         activeCount++;
   }
   if(activeCount >= InpMaxActiveZones) return;

   //--- Calculate entry, SL, TP
   double entryPrice, slPrice;
   double slBuffer = g_atrValue * InpSLBufferATR;

   if(sw.direction == SWEEP_BULLISH)
   {
      //--- Bullish: entry at OB high (top of demand zone), SL below OB low
      entryPrice = obHi;
      slPrice = obLo - slBuffer;
   }
   else
   {
      //--- Bearish: entry at OB low (bottom of supply zone), SL above OB high
      entryPrice = obLo;
      slPrice = obHi + slBuffer;
   }

   //--- Find TP from opposing liquidity
   string tpLabel;
   ENUM_TP_TYPE tpType;
   double tpPrice = FindOpposingLiquidity(sw.direction, entryPrice, slPrice, tpLabel, tpType);

   //--- Calculate RR
   double risk = MathAbs(entryPrice - slPrice);
   double reward = MathAbs(tpPrice - entryPrice);
   double rr = (risk > 0) ? reward / risk : 0;

   //--- Confluence score
   int confScore = CalculateConfluenceScore(sw.context, onTL, tlTouches);

   //--- Add zone
   int idx = g_zoneCount++;
   ArrayResize(g_zones, g_zoneCount);

   g_zones[idx].id                 = g_nextZoneId++;
   g_zones[idx].sweepBar           = sw.bar;
   g_zones[idx].sweepTime          = sw.time;
   g_zones[idx].sweepPrice         = sw.sweepPrice;
   g_zones[idx].levelPrice         = sw.levelPrice;
   g_zones[idx].direction          = sw.direction;
   g_zones[idx].context            = sw.context;
   g_zones[idx].displacementBar    = dispBar;
   g_zones[idx].displacementTime   = dispTime;
   g_zones[idx].displacementClose  = dispClose;
   g_zones[idx].obBar              = obBar;
   g_zones[idx].obHigh             = obHi;
   g_zones[idx].obLow              = obLo;
   g_zones[idx].obTime             = obTime;
   g_zones[idx].entryPrice         = entryPrice;
   g_zones[idx].slPrice            = slPrice;
   g_zones[idx].tpPrice            = tpPrice;
   g_zones[idx].tpType             = tpType;
   g_zones[idx].tpTargetLabel      = tpLabel;
   g_zones[idx].riskReward         = rr;
   g_zones[idx].status             = ZONE_PENDING;
   g_zones[idx].statusChangeTime   = sw.time;
   g_zones[idx].creationTime       = sw.time;
   g_zones[idx].creationBar        = sw.bar;
   g_zones[idx].approachAlertFired = false;
   g_zones[idx].triggerAlertFired  = false;
   g_zones[idx].resultAlertFired   = false;
   g_zones[idx].onTrendline        = onTL;
   g_zones[idx].trendlineTouches   = tlTouches;
   g_zones[idx].confidenceScore    = confScore;
}

//+------------------------------------------------------------------+
//| Update all zone statuses (lifecycle state machine)                 |
//+------------------------------------------------------------------+
void UpdateAllZoneStatuses(const double &high[], const double &low[],
                           const double &close[], const datetime &time[],
                           int rates_total)
{
   double approachDist = g_atrValue * InpApproachDistATR;

   for(int i = 0; i < g_zoneCount; i++)
   {
      //--- Skip terminal states
      if(g_zones[i].status == ZONE_HIT_TP ||
         g_zones[i].status == ZONE_HIT_SL ||
         g_zones[i].status == ZONE_INVALIDATED)
         continue;

      //--- Check age invalidation
      int ageBars = g_zones[i].creationBar; // In series mode, creationBar IS the age (bars from right)
      if(ageBars > InpMaxZoneAgeBars)
      {
         g_zones[i].status = ZONE_INVALIDATED;
         g_zones[i].statusChangeTime = time[0];
         g_invalidCount++;
         continue;
      }

      double currentHigh = high[0];
      double currentLow  = low[0];
      double currentClose = close[0];

      if(g_zones[i].direction == SWEEP_BULLISH)
      {
         //--- BULLISH zone: entry at OB high, OB below price

         //--- Check SL hit (close below SL)
         if(currentClose < g_zones[i].slPrice)
         {
            if(g_zones[i].status == ZONE_TRIGGERED)
            {
               g_zones[i].status = ZONE_HIT_SL;
               g_zones[i].statusChangeTime = time[0];
               g_slCount++;
               continue;
            }
            else
            {
               //--- Zone broken before trigger = invalidated
               g_zones[i].status = ZONE_INVALIDATED;
               g_zones[i].statusChangeTime = time[0];
               g_invalidCount++;
               continue;
            }
         }

         //--- Check TP hit (close above TP, only if triggered)
         if(g_zones[i].status == ZONE_TRIGGERED && currentClose >= g_zones[i].tpPrice)
         {
            g_zones[i].status = ZONE_HIT_TP;
            g_zones[i].statusChangeTime = time[0];
            g_tpCount++;
            continue;
         }

         //--- Check trigger (wick into OB zone, close above entry)
         if(g_zones[i].status == ZONE_APPROACHING || g_zones[i].status == ZONE_PENDING)
         {
            if(currentLow <= g_zones[i].obHigh && currentLow >= g_zones[i].obLow &&
               currentClose > g_zones[i].entryPrice)
            {
               g_zones[i].status = ZONE_TRIGGERED;
               g_zones[i].statusChangeTime = time[0];
               continue;
            }

            //--- Zone broken (close below OB low)
            if(currentClose < g_zones[i].obLow)
            {
               g_zones[i].status = ZONE_INVALIDATED;
               g_zones[i].statusChangeTime = time[0];
               g_invalidCount++;
               continue;
            }
         }

         //--- Check approaching
         if(g_zones[i].status == ZONE_PENDING)
         {
            double distToEntry = currentLow - g_zones[i].entryPrice;
            if(distToEntry >= 0 && distToEntry <= approachDist)
            {
               g_zones[i].status = ZONE_APPROACHING;
               g_zones[i].statusChangeTime = time[0];
            }
         }
         else if(g_zones[i].status == ZONE_APPROACHING)
         {
            //--- If price moved away, back to pending
            double distToEntry = currentLow - g_zones[i].entryPrice;
            if(distToEntry > approachDist * 2)
            {
               g_zones[i].status = ZONE_PENDING;
               g_zones[i].statusChangeTime = time[0];
            }
         }
      }
      else
      {
         //--- BEARISH zone: entry at OB low, OB above price

         //--- Check SL hit
         if(currentClose > g_zones[i].slPrice)
         {
            if(g_zones[i].status == ZONE_TRIGGERED)
            {
               g_zones[i].status = ZONE_HIT_SL;
               g_zones[i].statusChangeTime = time[0];
               g_slCount++;
               continue;
            }
            else
            {
               g_zones[i].status = ZONE_INVALIDATED;
               g_zones[i].statusChangeTime = time[0];
               g_invalidCount++;
               continue;
            }
         }

         //--- Check TP hit
         if(g_zones[i].status == ZONE_TRIGGERED && currentClose <= g_zones[i].tpPrice)
         {
            g_zones[i].status = ZONE_HIT_TP;
            g_zones[i].statusChangeTime = time[0];
            g_tpCount++;
            continue;
         }

         //--- Check trigger
         if(g_zones[i].status == ZONE_APPROACHING || g_zones[i].status == ZONE_PENDING)
         {
            if(currentHigh >= g_zones[i].obLow && currentHigh <= g_zones[i].obHigh &&
               currentClose < g_zones[i].entryPrice)
            {
               g_zones[i].status = ZONE_TRIGGERED;
               g_zones[i].statusChangeTime = time[0];
               continue;
            }

            //--- Zone broken
            if(currentClose > g_zones[i].obHigh)
            {
               g_zones[i].status = ZONE_INVALIDATED;
               g_zones[i].statusChangeTime = time[0];
               g_invalidCount++;
               continue;
            }
         }

         //--- Check approaching
         if(g_zones[i].status == ZONE_PENDING)
         {
            double distToEntry = g_zones[i].entryPrice - currentHigh;
            if(distToEntry >= 0 && distToEntry <= approachDist)
            {
               g_zones[i].status = ZONE_APPROACHING;
               g_zones[i].statusChangeTime = time[0];
            }
         }
         else if(g_zones[i].status == ZONE_APPROACHING)
         {
            double distToEntry = g_zones[i].entryPrice - currentHigh;
            if(distToEntry > approachDist * 2)
            {
               g_zones[i].status = ZONE_PENDING;
               g_zones[i].statusChangeTime = time[0];
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update trendline status (check for breaks)                         |
//+------------------------------------------------------------------+
void UpdateTrendlineStatus(const double &high[], const double &low[],
                           const double &close[], const datetime &time[],
                           int maxBar)
{
   double breakTol = g_atrValue * InpTrendlineTouchTol * 3;

   for(int i = 0; i < g_trendlineCount; i++)
   {
      if(g_trendlines[i].broken) continue;

      //--- Project line to current bar
      double projPrice = ProjectTrendlinePrice(g_trendlines[i], 0);

      if(g_trendlines[i].direction == 1) // Uptrend
      {
         //--- Break = close below projected line
         if(close[0] < projPrice - breakTol)
         {
            g_trendlines[i].broken = true;
            g_trendlines[i].breakTime = time[0];
         }
      }
      else // Downtrend
      {
         //--- Break = close above projected line
         if(close[0] > projPrice + breakTol)
         {
            g_trendlines[i].broken = true;
            g_trendlines[i].breakTime = time[0];
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Enforce max active zones                                           |
//+------------------------------------------------------------------+
void EnforceMaxZones()
{
   //--- Count active zones
   int activeCount = 0;
   for(int i = 0; i < g_zoneCount; i++)
   {
      if(g_zones[i].status == ZONE_PENDING || g_zones[i].status == ZONE_APPROACHING)
         activeCount++;
   }

   //--- Remove oldest terminal zones if total is too high
   while(g_zoneCount > InpMaxActiveZones * 3)
   {
      //--- Find oldest terminal zone
      int oldestIdx = -1;
      int oldestBar = -1;
      for(int i = 0; i < g_zoneCount; i++)
      {
         if(g_zones[i].status == ZONE_HIT_TP ||
            g_zones[i].status == ZONE_HIT_SL ||
            g_zones[i].status == ZONE_INVALIDATED)
         {
            if(g_zones[i].creationBar > oldestBar)
            {
               oldestBar = g_zones[i].creationBar;
               oldestIdx = i;
            }
         }
      }

      if(oldestIdx < 0) break;

      //--- Remove by shifting array
      for(int j = oldestIdx; j < g_zoneCount - 1; j++)
         g_zones[j] = g_zones[j + 1];
      g_zoneCount--;
      ArrayResize(g_zones, g_zoneCount);
   }
}

//+------------------------------------------------------------------+
//| Alert helpers                                                      |
//+------------------------------------------------------------------+
void FireAlert(string message)
{
   if(InpAlertPopup) Alert(message);
   if(InpAlertSound) PlaySound("alert.wav");
   if(InpAlertPush)  SendNotification(message);
}

void CheckApproachAlerts()
{
   if(!InpAlertOnApproach) return;

   for(int i = 0; i < g_zoneCount; i++)
   {
      if(g_zones[i].status == ZONE_APPROACHING && !g_zones[i].approachAlertFired)
      {
         string dir = (g_zones[i].direction == SWEEP_BULLISH) ? "BUY" : "SELL";
         FireAlert("SniperEntry: " + dir + " zone approaching on " + _Symbol +
                  " | Entry: " + DoubleToString(g_zones[i].entryPrice, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
                  " | Conf: " + IntegerToString(g_zones[i].confidenceScore) + "/4");
         g_zones[i].approachAlertFired = true;
      }
   }
}

void CheckTriggerAlerts()
{
   if(!InpAlertOnTrigger) return;

   for(int i = 0; i < g_zoneCount; i++)
   {
      if(g_zones[i].status == ZONE_TRIGGERED && !g_zones[i].triggerAlertFired)
      {
         string dir = (g_zones[i].direction == SWEEP_BULLISH) ? "BUY" : "SELL";
         FireAlert("SniperEntry: " + dir + " TRIGGERED on " + _Symbol +
                  " | Entry: " + DoubleToString(g_zones[i].entryPrice, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
                  " | TP: " + DoubleToString(g_zones[i].tpPrice, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
                  " | RR: 1:" + DoubleToString(g_zones[i].riskReward, 1));
         g_zones[i].triggerAlertFired = true;
      }
   }
}

void CheckResultAlerts()
{
   if(!InpAlertOnResult) return;

   for(int i = 0; i < g_zoneCount; i++)
   {
      if(g_zones[i].resultAlertFired) continue;

      if(g_zones[i].status == ZONE_HIT_TP)
      {
         string dir = (g_zones[i].direction == SWEEP_BULLISH) ? "BUY" : "SELL";
         FireAlert("SniperEntry: " + dir + " HIT TP on " + _Symbol +
                  " | " + g_zones[i].tpTargetLabel + " | RR: 1:" + DoubleToString(g_zones[i].riskReward, 1));
         g_zones[i].resultAlertFired = true;
      }
      else if(g_zones[i].status == ZONE_HIT_SL)
      {
         string dir = (g_zones[i].direction == SWEEP_BULLISH) ? "BUY" : "SELL";
         FireAlert("SniperEntry: " + dir + " HIT SL on " + _Symbol);
         g_zones[i].resultAlertFired = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Draw all entry zones                                               |
//+------------------------------------------------------------------+
void DrawAllZones(const datetime &time[], const double &high[],
                  const double &low[], int totalBars)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = 0; i < g_zoneCount; i++)
   {
      EntryZone z = g_zones[i];
      string idStr = IntegerToString(z.id);

      //--- Determine zone color based on status
      color zoneColor;
      string statusText;

      switch(z.status)
      {
         case ZONE_PENDING:
            zoneColor = (z.direction == SWEEP_BULLISH) ? InpDemandColor : InpSupplyColor;
            statusText = "PENDING";
            break;
         case ZONE_APPROACHING:
            zoneColor = InpApproachColor;
            statusText = "APPROACHING !!!";
            break;
         case ZONE_TRIGGERED:
            zoneColor = InpTriggeredColor;
            statusText = "TRIGGERED";
            break;
         case ZONE_HIT_TP:
            zoneColor = InpTPColor;
            statusText = "HIT TP";
            break;
         case ZONE_HIT_SL:
            zoneColor = InpSLColor;
            statusText = "HIT SL";
            break;
         case ZONE_INVALIDATED:
            zoneColor = InpInvalidColor;
            statusText = "INVALID";
            break;
         default:
            zoneColor = InpInvalidColor;
            statusText = "?";
      }

      //--- Skip drawing invalidated zones older than 20 bars
      if(z.status == ZONE_INVALIDATED && z.creationBar > 20) continue;

      //--- Draw OB rectangle
      if(InpShowZones)
      {
         int zoneEndBar = MathMax(z.obBar - InpZoneExtensionBars, 0);
         if(z.obBar < totalBars && zoneEndBar < totalBars)
         {
            string rectName = g_objPrefix + "ZN_" + idStr;
            if(ObjectCreate(0, rectName, OBJ_RECTANGLE, 0,
                           z.obTime, z.obHigh,
                           time[zoneEndBar], z.obLow))
            {
               ObjectSetInteger(0, rectName, OBJPROP_COLOR, zoneColor);
               ObjectSetInteger(0, rectName, OBJPROP_STYLE, STYLE_SOLID);
               ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 1);
               ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
               ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
               ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
               ObjectSetInteger(0, rectName, OBJPROP_HIDDEN, true);
            }
         }

         //--- Status label with confluence score
         string label = statusText + " [" + IntegerToString(z.confidenceScore) + "/4]";
         string labelName = g_objPrefix + "ZL_" + idStr;
         bool above = (z.direction == SWEEP_BEARISH);
         double labelPrice = above ? z.obHigh : z.obLow;
         DrawLabel(labelName, z.obTime, labelPrice, label, zoneColor, above, InpFontSize);
      }

      //--- Draw SL/TP lines (only for active zones)
      if(InpShowSLTP && z.status != ZONE_INVALIDATED)
      {
         int lineEndBar = MathMax(z.obBar - InpZoneExtensionBars, 0);
         if(z.obBar < totalBars && lineEndBar < totalBars)
         {
            //--- Entry line (solid)
            string entryName = g_objPrefix + "EN_" + idStr;
            DrawHorizontalLine(entryName, z.obTime, time[lineEndBar],
                             z.entryPrice, InpEntryColor, 1, STYLE_SOLID);

            //--- SL line (dashed)
            string slName = g_objPrefix + "SL_" + idStr;
            DrawHorizontalLine(slName, z.obTime, time[lineEndBar],
                             z.slPrice, InpSLColor, 1, STYLE_DASH);

            //--- TP line (dashed)
            string tpName = g_objPrefix + "TP_" + idStr;
            DrawHorizontalLine(tpName, z.obTime, time[lineEndBar],
                             z.tpPrice, InpTPColor, 1, STYLE_DASH);
         }

         //--- TP target label
         if(InpShowTargets && z.tpTargetLabel != "")
         {
            string tpLabelName = g_objPrefix + "TPL_" + idStr;
            bool tpAbove = (z.direction == SWEEP_BULLISH);
            DrawLabel(tpLabelName, z.obTime, z.tpPrice,
                     "Target: " + z.tpTargetLabel, InpLiqTargetColor, tpAbove, InpFontSize - 1);
         }

         //--- RR label
         string rrName = g_objPrefix + "RR_" + idStr;
         string rrText = "RR 1:" + DoubleToString(z.riskReward, 1);
         DrawLabel(rrName, z.obTime, z.entryPrice, rrText, InpEntryColor,
                  (z.direction == SWEEP_BULLISH), InpFontSize - 1);
      }

      //--- Draw sweep arrow
      if(InpShowStructure && z.sweepBar < totalBars)
      {
         bool isBear = (z.direction == SWEEP_BEARISH);
         int arrowCode = isBear ? 234 : 233;
         string arrowName = g_objPrefix + "SA_" + idStr;

         if(!ObjectCreate(0, arrowName, OBJ_ARROW, 0, z.sweepTime, z.sweepPrice))
            ObjectMove(0, arrowName, 0, z.sweepTime, z.sweepPrice);

         ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
         ObjectSetInteger(0, arrowName, OBJPROP_COLOR, InpSweepArrowColor);
         ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR, isBear ? ANCHOR_BOTTOM : ANCHOR_TOP);
         ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, true);
      }

      //--- Trendline confluence label
      if(z.onTrendline)
      {
         string tlName = g_objPrefix + "TLC_" + idStr;
         string tlText = "On TL (" + IntegerToString(z.trendlineTouches) + "t)";
         if(z.obBar < totalBars)
         {
            bool tAbove = (z.direction == SWEEP_BULLISH);
            double tPrice = tAbove ? z.obLow - g_atrValue * 0.15 : z.obHigh + g_atrValue * 0.15;
            DrawLabel(tlName, z.obTime, tPrice, tlText, InpTrendUpColor, !tAbove, InpFontSize - 1);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw equal level lines                                             |
//+------------------------------------------------------------------+
void DrawEqualLevels(const datetime &time[], int totalBars)
{
   for(int i = 0; i < g_equalLevelCount; i++)
   {
      EqualLevel eq = g_equalLevels[i];
      if(eq.swept) continue; // Hide swept levels

      color lineColor = eq.isHigh ? InpEqualHighColor : InpEqualLowColor;

      int lineStartBar = eq.startBar;
      int lineEndBar = 0;
      if(lineStartBar >= totalBars) lineStartBar = totalBars - 1;
      if(lineStartBar < 0) lineStartBar = 0;

      string lineName = g_objPrefix + "EQ_" + IntegerToString(i);
      DrawHorizontalLine(lineName, time[lineStartBar], time[lineEndBar],
                        eq.price, lineColor, 2, STYLE_SOLID);

      string labelText = eq.isHigh ? ("EQH x" + IntegerToString(eq.touches))
                                    : ("EQL x" + IntegerToString(eq.touches));
      string labelName = g_objPrefix + "EQL_" + IntegerToString(i);
      DrawLabel(labelName, time[lineStartBar], eq.price,
               labelText, lineColor, eq.isHigh, InpFontSize);
   }
}

//+------------------------------------------------------------------+
//| Draw trendlines                                                    |
//+------------------------------------------------------------------+
void DrawTrendlines(const datetime &time[], int totalBars)
{
   for(int i = 0; i < g_trendlineCount; i++)
   {
      TrendLine tl = g_trendlines[i];

      color clr;
      if(tl.broken)
         clr = InpTrendBrokenColor;
      else
         clr = (tl.direction == 1) ? InpTrendUpColor : InpTrendDownColor;

      //--- Draw trendline from start to projected forward
      int projBar = MathMax(tl.endBar - 30, 0); // Extend 30 bars beyond last point
      if(projBar >= totalBars) projBar = totalBars - 1;

      double projPrice = ProjectTrendlinePrice(tl, projBar);

      string name = g_objPrefix + "TL_" + IntegerToString(i);
      if(tl.startBar < totalBars && projBar < totalBars)
      {
         if(!ObjectCreate(0, name, OBJ_TREND, 0,
                         time[tl.startBar], tl.startPrice,
                         time[projBar], projPrice))
         {
            ObjectMove(0, name, 0, time[tl.startBar], tl.startPrice);
            ObjectMove(0, name, 1, time[projBar], projPrice);
         }

         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, tl.broken ? 1 : 2);
         ObjectSetInteger(0, name, OBJPROP_STYLE, tl.broken ? STYLE_DOT : STYLE_SOLID);
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }

      //--- Touch count label
      if(!tl.broken && tl.endBar < totalBars)
      {
         string labelName = g_objPrefix + "TLL_" + IntegerToString(i);
         string labelText = "TL " + IntegerToString(tl.touchCount) + "t";
         DrawLabel(labelName, time[tl.endBar], tl.endPrice, labelText,
                  clr, (tl.direction == -1), InpFontSize - 1);
      }
   }
}

//+------------------------------------------------------------------+
//| Build dashboard                                                    |
//+------------------------------------------------------------------+
void BuildDashboard()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   string dash = "";
   string sep = StringFormat("%s\n", "========================================");

   dash += sep;
   dash += " SniperEntry v1.0 | " + _Symbol + " " + GetTimeframeString() + "\n";
   dash += sep;

   //--- Count active zones
   int activeCount = 0;
   for(int i = 0; i < g_zoneCount; i++)
      if(g_zones[i].status == ZONE_PENDING || g_zones[i].status == ZONE_APPROACHING)
         activeCount++;

   dash += " ATR(" + IntegerToString(InpATRPeriod) + "): " + DoubleToString(g_atrValue, digits)
         + " | Zones: " + IntegerToString(activeCount) + "/" + IntegerToString(InpMaxActiveZones)
         + "\n\n";

   //--- Show active zones
   for(int i = 0; i < g_zoneCount; i++)
   {
      EntryZone z = g_zones[i];

      //--- Only show active + recently resolved
      if(z.status == ZONE_INVALIDATED && z.creationBar > 20) continue;

      string dir = (z.direction == SWEEP_BULLISH) ? "BUY" : "SELL";
      string stat = "";
      switch(z.status)
      {
         case ZONE_PENDING:     stat = "PENDING"; break;
         case ZONE_APPROACHING: stat = "APPROACHING"; break;
         case ZONE_TRIGGERED:   stat = "TRIGGERED"; break;
         case ZONE_HIT_TP:      stat = "HIT TP"; break;
         case ZONE_HIT_SL:      stat = "HIT SL"; break;
         case ZONE_INVALIDATED: stat = "INVALID"; break;
      }

      dash += " [" + IntegerToString(z.id) + "] " + dir + " " + stat
            + " [" + IntegerToString(z.confidenceScore) + "/4]"
            + "  Entry: " + DoubleToString(z.entryPrice, digits)
            + " | SL: " + DoubleToString(z.slPrice, digits)
            + " | TP: " + DoubleToString(z.tpPrice, digits) + "\n";

      dash += "     Target: " + z.tpTargetLabel
            + " | RR 1:" + DoubleToString(z.riskReward, 1)
            + " | Age: " + IntegerToString(z.creationBar) + " bars\n";

      //--- Context + confluence details
      string ctxStr = "";
      if(z.context == CTX_RANGE_SWEEP) ctxStr = "RANGE - Fuel";
      else if(z.context == CTX_HTF_EXTREME) ctxStr = "HTF EXTREME";

      string details = "     Context: " + ctxStr;
      if(z.onTrendline) details += " | On TL (" + IntegerToString(z.trendlineTouches) + "t)";

      dash += details + "\n";

      if(z.status == ZONE_APPROACHING)
         dash += "     >> Price approaching entry! <<\n";

      dash += "\n";
   }

   //--- Trendline summary
   int bullTL = 0, bearTL = 0;
   for(int i = 0; i < g_trendlineCount; i++)
   {
      if(g_trendlines[i].broken) continue;
      if(g_trendlines[i].direction == 1) bullTL++;
      else bearTL++;
   }

   if(bullTL > 0 || bearTL > 0)
      dash += " Trendlines: " + IntegerToString(bullTL) + " bull, "
            + IntegerToString(bearTL) + " bear (active)\n";

   dash += sep;
   dash += " TP: " + IntegerToString(g_tpCount)
         + " | SL: " + IntegerToString(g_slCount)
         + " | Invalidated: " + IntegerToString(g_invalidCount) + "\n";
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
//| Draw text label                                                    |
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
//| Draw horizontal line segment                                       |
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
//| Timer event — check for wave trendline every 5 seconds             |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(ObjectFind(0, InpWaveTrendline) < 0)
   {
      ClearWaveObjects();
      return;
   }

   datetime t0 = (datetime)ObjectGetInteger(0, InpWaveTrendline, OBJPROP_TIME, 0);
   datetime t1 = (datetime)ObjectGetInteger(0, InpWaveTrendline, OBJPROP_TIME, 1);
   double   p0 = ObjectGetDouble(0, InpWaveTrendline, OBJPROP_PRICE, 0);
   double   p1 = ObjectGetDouble(0, InpWaveTrendline, OBJPROP_PRICE, 1);

   if(t0 == 0 || t1 == 0 || p0 == 0 || p1 == 0)
      return;

   ProjectWaves(t0, p0, t1, p1);
}

//+------------------------------------------------------------------+
//| Project waves 2-5 from a manually drawn Wave 1 trendline           |
//+------------------------------------------------------------------+
void ProjectWaves(datetime t0, double p0, datetime t1, double p1)
{
   double wave1Length = p1 - p0;
   double sign = (wave1Length >= 0) ? 1.0 : -1.0;

   // Wave 2: 61.8% retracement of Wave 1
   double p2 = p1 - wave1Length * 0.618;

   // Wave 3: 161.8% extension from Wave 0
   double p3 = p0 + sign * MathAbs(wave1Length) * 1.618;

   // Wave 4: 38.2% retracement of Wave 3
   double wave3Length = p3 - p2;
   double p4 = p3 - wave3Length * 0.382;

   // Wave 5: equal to Wave 1
   double p5 = p4 + wave1Length;

   datetime t2 = t1 + InpWaveSpacingMinutes * 60;
   datetime t3 = t2 + InpWaveSpacingMinutes * 60;
   datetime t4 = t3 + InpWaveSpacingMinutes * 60;
   datetime t5 = t4 + InpWaveSpacingMinutes * 60;

   ClearWaveObjects();

   DrawWaveArrowLine(g_wavePrefix + "W1", t0, p0, t1, p1, InpWave1Color);
   DrawWaveArrowLine(g_wavePrefix + "W2", t1, p1, t2, p2, InpWave2Color);
   DrawWaveArrowLine(g_wavePrefix + "W3", t2, p2, t3, p3, InpWave3Color);
   DrawWaveArrowLine(g_wavePrefix + "W4", t3, p3, t4, p4, InpWave4Color);
   DrawWaveArrowLine(g_wavePrefix + "W5", t4, p4, t5, p5, InpWave5Color);

   DrawWaveLabel(g_wavePrefix + "L0", t0, p0, "0");
   DrawWaveLabel(g_wavePrefix + "L1", t1, p1, "1");
   DrawWaveLabel(g_wavePrefix + "L2", t2, p2, "2");
   DrawWaveLabel(g_wavePrefix + "L3", t3, p3, "3");
   DrawWaveLabel(g_wavePrefix + "L4", t4, p4, "4");
   DrawWaveLabel(g_wavePrefix + "L5", t5, p5, "5");

   // Fibonacci retracement on Wave 1
   if(InpFiboReversed)
      DrawWaveFibonacci(g_wavePrefix + "Fibo", t1, p1, t0, p0);
   else
      DrawWaveFibonacci(g_wavePrefix + "Fibo", t0, p0, t1, p1);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw arrowed line for wave segment                                 |
//+------------------------------------------------------------------+
void DrawWaveArrowLine(string name, datetime t1, double p1,
                       datetime t2, double p2, color clr)
{
   if(!ObjectCreate(0, name, OBJ_ARROWED_LINE, 0, t1, p1, t2, p2))
   {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Draw wave number label                                             |
//+------------------------------------------------------------------+
void DrawWaveLabel(string name, datetime t, double p, string txt)
{
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, p))
      ObjectMove(0, name, 0, t, p);

   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpWaveLabelColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Draw Fibonacci retracement on Wave 1                               |
//+------------------------------------------------------------------+
void DrawWaveFibonacci(string name, datetime t1, double p1,
                       datetime t2, double p2)
{
   if(!ObjectCreate(0, name, OBJ_FIBO, 0, t1, p1, t2, p2))
   {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
   }

   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpFiboColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_LEVELS, 7);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   double levels[]    = {0.0, 0.382, 0.5, 0.618, 1.0, 1.618, 2.618};
   string levelText[] = {"0.0", "38.2%", "50.0%", "61.8%", "100.0%", "161.8%", "261.8%"};

   for(int i = 0; i < 7; i++)
   {
      ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, i, levels[i]);
      ObjectSetString(0, name, OBJPROP_LEVELTEXT, i, levelText[i]);
      ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, i, InpFiboColor);
   }
}

//+------------------------------------------------------------------+
//| Clear all wave projection objects (WV_ prefix)                     |
//+------------------------------------------------------------------+
void ClearWaveObjects()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_wavePrefix) == 0)
         ObjectDelete(0, name);
   }
}
//+------------------------------------------------------------------+
