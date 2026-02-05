//+------------------------------------------------------------------+
//|                                     MarketStructureChannels.mq5   |
//|                              TradeMind Market Structure Indicator |
//|            Draws channels with BOS, BMS, CHoCH, HH/HL/LH/LL,    |
//|            Range H/L, Internal & External structure breaks        |
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
enum ENUM_STRUCT_TYPE
{
   STRUCT_HH = 0,    // Higher High
   STRUCT_HL,         // Higher Low
   STRUCT_LH,         // Lower High
   STRUCT_LL,         // Lower Low
};

enum ENUM_BREAK_TYPE
{
   BREAK_NONE = 0,
   BREAK_BOS_BULL,    // BOS bullish (continuation)
   BREAK_BOS_BEAR,    // BOS bearish (continuation)
   BREAK_CHOCH_BULL,  // CHoCH bullish reversal
   BREAK_CHOCH_BEAR,  // CHoCH bearish reversal
};

enum ENUM_TREND_STATE
{
   TREND_BULLISH = 0,
   TREND_BEARISH,
   TREND_RANGE,
};

//+------------------------------------------------------------------+
//| Input parameters                                                   |
//+------------------------------------------------------------------+
input int      InpSwingStrength      = 5;              // Swing strength (bars each side)
input int      InpMaxBars            = 500;            // Max bars to analyze
input int      InpLevelBars          = 20;             // Level line length (bars forward from swing)
input bool     InpShowLevels         = true;           // Show horizontal swing levels
input bool     InpShowSwingLabels    = true;           // Show HH/HL/LH/LL labels
input bool     InpShowBOS            = true;           // Show BOS labels
input bool     InpShowCHoCH          = true;           // Show CHoCH labels
input bool     InpShowRangeZones     = false;          // Show range (accumulation/distribution) zones
input bool     InpShowInternalBreaks = false;          // Show internal structure breaks
input int      InpInternalStrength   = 2;              // Internal structure swing strength (smaller)

//--- Color inputs
input color    InpBullLevelColor     = clrDodgerBlue;  // Bullish level color
input color    InpBearLevelColor     = clrCrimson;     // Bearish level color
input color    InpBOSColor           = clrDodgerBlue;  // BOS label color
input color    InpCHoCHColor         = clrOrangeRed;   // CHoCH label color
input color    InpHHColor            = clrLime;         // HH label color
input color    InpHLColor            = clrMediumSeaGreen; // HL label color
input color    InpLHColor            = clrTomato;       // LH label color
input color    InpLLColor            = clrRed;          // LL label color
input color    InpRangeColor         = clrGold;         // Range zone color
input color    InpInternalColor      = clrMediumPurple; // Internal break color
input int      InpLevelWidth         = 1;              // Level line width
input int      InpFontSize           = 8;              // Label font size

//+------------------------------------------------------------------+
//| Structures                                                         |
//+------------------------------------------------------------------+
struct SwingPoint
{
   int            bar;          // Bar index
   double         price;        // Price level
   bool           isHigh;       // true=swing high, false=swing low
   ENUM_STRUCT_TYPE structType; // HH/HL/LH/LL classification
   datetime       time;         // Bar time
};

struct StructureBreak
{
   int            bar;          // Bar where break occurred
   double         price;        // Price level of break
   ENUM_BREAK_TYPE breakType;   // BOS or CHoCH
   bool           isInternal;   // Internal (LTF) vs External (HTF) break
   datetime       time;         // Bar time
   double         fromPrice;    // The swing point that was broken
};

struct RangeZone
{
   double         high;         // Range high
   double         low;          // Range low
   int            startBar;     // Start bar
   int            endBar;       // End bar (0 = still active)
   datetime       startTime;    // Start time
   datetime       endTime;      // End time
   bool           isActive;     // Still accumulating
};

//+------------------------------------------------------------------+
//| Global variables                                                   |
//+------------------------------------------------------------------+
SwingPoint       g_swingHighs[];
SwingPoint       g_swingLows[];
int              g_swingHighCount = 0;
int              g_swingLowCount  = 0;

// Internal (smaller) swing points for internal structure
SwingPoint       g_intSwingHighs[];
SwingPoint       g_intSwingLows[];
int              g_intSwingHighCount = 0;
int              g_intSwingLowCount  = 0;

StructureBreak   g_breaks[];
int              g_breakCount = 0;

RangeZone        g_ranges[];
int              g_rangeCount = 0;

ENUM_TREND_STATE g_currentTrend = TREND_RANGE;

string           g_objPrefix = "MSC_";
int              g_lastCalculatedBars = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                           |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("MarketStructureChannels v2.0 initializing...");
   Print("Swing Strength: ", InpSwingStrength, " | Level Bars: ", InpLevelBars, " | Max Bars: ", InpMaxBars);

   //--- Clean all objects on init
   CleanAllObjects();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanAllObjects();
   Print("MarketStructureChannels deinitialized");
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

   //--- Determine analysis range
   int barsToAnalyze = MathMin(InpMaxBars, rates_total);
   int startBar = barsToAnalyze - 1;

   //--- Clean previous objects and reset arrays
   CleanAllObjects();
   ResetArrays();

   //--- Set arrays as series (index 0 = current bar)
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(close, true);

   //--- Step 1: Detect external swing points (main structure)
   DetectSwingPoints(high, low, time, startBar, InpSwingStrength,
                     g_swingHighs, g_swingHighCount,
                     g_swingLows, g_swingLowCount);

   //--- Step 2: Classify swing points as HH/HL/LH/LL
   ClassifySwingPoints();

   //--- Step 3: Determine trend state and detect BOS/CHoCH
   DetectStructureBreaks(high, low, close, time, startBar);

   //--- Step 4: Detect internal swing points (smaller structure)
   if(InpShowInternalBreaks)
   {
      DetectSwingPoints(high, low, time, startBar, InpInternalStrength,
                        g_intSwingHighs, g_intSwingHighCount,
                        g_intSwingLows, g_intSwingLowCount);
      DetectInternalBreaks(high, low, close, time, startBar);
   }

   //--- Step 5: Detect range zones (accumulation/distribution)
   if(InpShowRangeZones)
      DetectRangeZones(high, low, time, startBar);

   //--- Step 6: Draw everything
   DrawAllObjects(high, low, time);

   return rates_total;
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

   //--- Scan from oldest to newest (right to left in series)
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
         swingHighs[idx].bar      = i;
         swingHighs[idx].price    = high[i];
         swingHighs[idx].isHigh   = true;
         swingHighs[idx].time     = time[i];
         swingHighs[idx].structType = STRUCT_HH; // Default, classified later
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
         swingLows[idx].bar      = i;
         swingLows[idx].price    = low[i];
         swingLows[idx].isHigh   = false;
         swingLows[idx].time     = time[i];
         swingLows[idx].structType = STRUCT_HL; // Default, classified later
      }
   }
}

//+------------------------------------------------------------------+
//| Classify swing points as HH/HL/LH/LL                              |
//+------------------------------------------------------------------+
void ClassifySwingPoints()
{
   //--- Classify swing highs: compare each to previous swing high
   //--- Swing arrays are ordered from oldest (index 0) to newest
   for(int i = 1; i < g_swingHighCount; i++)
   {
      if(g_swingHighs[i].price > g_swingHighs[i - 1].price)
         g_swingHighs[i].structType = STRUCT_HH;
      else
         g_swingHighs[i].structType = STRUCT_LH;
   }

   //--- Classify swing lows: compare each to previous swing low
   for(int i = 1; i < g_swingLowCount; i++)
   {
      if(g_swingLows[i].price > g_swingLows[i - 1].price)
         g_swingLows[i].structType = STRUCT_HL;
      else
         g_swingLows[i].structType = STRUCT_LL;
   }
}

//+------------------------------------------------------------------+
//| Detect BOS and CHoCH from structure breaks                         |
//+------------------------------------------------------------------+
void DetectStructureBreaks(const double &high[], const double &low[],
                           const double &close[], const datetime &time[],
                           int maxBar)
{
   g_breakCount = 0;
   g_currentTrend = TREND_RANGE;

   //--- We need at least 2 swing highs and 2 swing lows to detect breaks
   if(g_swingHighCount < 2 || g_swingLowCount < 2)
      return;

   //--- Determine initial trend from first pair of swings
   //--- Merge swing highs and lows into chronological order by bar index
   //--- (bar index: higher = older in series mode)
   SwingPoint allSwings[];
   int totalSwings = g_swingHighCount + g_swingLowCount;
   ArrayResize(allSwings, totalSwings);

   int idx = 0;
   for(int i = 0; i < g_swingHighCount; i++)
   {
      allSwings[idx] = g_swingHighs[i];
      idx++;
   }
   for(int i = 0; i < g_swingLowCount; i++)
   {
      allSwings[idx] = g_swingLows[i];
      idx++;
   }

   //--- Sort by bar index descending (oldest first in series)
   SortSwingsByBar(allSwings, totalSwings);

   //--- Determine initial trend from first few classified swings
   for(int i = 0; i < totalSwings; i++)
   {
      if(allSwings[i].isHigh)
      {
         if(allSwings[i].structType == STRUCT_HH)
         { g_currentTrend = TREND_BULLISH; break; }
         else if(allSwings[i].structType == STRUCT_LH)
         { g_currentTrend = TREND_BEARISH; break; }
      }
      else
      {
         if(allSwings[i].structType == STRUCT_HL)
         { g_currentTrend = TREND_BULLISH; break; }
         else if(allSwings[i].structType == STRUCT_LL)
         { g_currentTrend = TREND_BEARISH; break; }
      }
   }

   //--- Walk through swing points and detect BOS / CHoCH
   //--- Track the last confirmed swing high and low
   double lastSwingHigh  = 0;
   double lastSwingLow   = 999999;
   int    lastSwingHighBar = 0;
   int    lastSwingLowBar  = 0;

   // Initialize from first swings
   if(g_swingHighCount > 0)
   {
      lastSwingHigh    = g_swingHighs[0].price;
      lastSwingHighBar = g_swingHighs[0].bar;
   }
   if(g_swingLowCount > 0)
   {
      lastSwingLow    = g_swingLows[0].price;
      lastSwingLowBar = g_swingLows[0].bar;
   }

   //--- Walk chronologically (oldest to newest)
   for(int i = 1; i < totalSwings; i++)
   {
      SwingPoint sp = allSwings[i];

      if(sp.isHigh)
      {
         //--- Check if price broke above previous swing high
         //--- Scan bars between previous swing high and this swing for a close above
         if(lastSwingHigh > 0 && sp.price > lastSwingHigh)
         {
            //--- Find the bar that actually closed above the level
            int breakBar = FindBreakBar(close, high, sp.bar, lastSwingHighBar, lastSwingHigh, true);

            if(breakBar >= 0)
            {
               ENUM_BREAK_TYPE bType;

               if(g_currentTrend == TREND_BULLISH)
               {
                  //--- Continuation: BOS bullish
                  bType = BREAK_BOS_BULL;
               }
               else
               {
                  //--- Reversal from bearish: CHoCH bullish
                  bType = BREAK_CHOCH_BULL;
                  g_currentTrend = TREND_BULLISH;
               }

               AddBreak(breakBar, lastSwingHigh, bType, false, time[breakBar], sp.price);
            }
         }

         lastSwingHigh    = sp.price;
         lastSwingHighBar = sp.bar;
      }
      else
      {
         //--- Check if price broke below previous swing low
         if(lastSwingLow < 999999 && sp.price < lastSwingLow)
         {
            int breakBar = FindBreakBar(close, low, sp.bar, lastSwingLowBar, lastSwingLow, false);

            if(breakBar >= 0)
            {
               ENUM_BREAK_TYPE bType;

               if(g_currentTrend == TREND_BEARISH)
               {
                  //--- Continuation: BOS bearish
                  bType = BREAK_BOS_BEAR;
               }
               else
               {
                  //--- Reversal from bullish: CHoCH bearish
                  bType = BREAK_CHOCH_BEAR;
                  g_currentTrend = TREND_BEARISH;
               }

               AddBreak(breakBar, lastSwingLow, bType, false, time[breakBar], sp.price);
            }
         }

         lastSwingLow    = sp.price;
         lastSwingLowBar = sp.bar;
      }
   }
}

//+------------------------------------------------------------------+
//| Find the bar where price closed beyond a level                     |
//+------------------------------------------------------------------+
int FindBreakBar(const double &close[], const double &hl[],
                 int toBar, int fromBar, double level, bool breakAbove)
{
   //--- Scan from fromBar towards toBar (older to newer in series)
   //--- In series mode: fromBar > toBar (higher index = older)
   int start = fromBar - 1;
   int end   = toBar;

   if(start < 0) start = 0;
   if(end < 0) end = 0;

   for(int i = start; i >= end; i--)
   {
      if(breakAbove && close[i] > level)
         return i;
      if(!breakAbove && close[i] < level)
         return i;
   }

   return -1;
}

//+------------------------------------------------------------------+
//| Detect internal structure breaks (LTF confirmation)                |
//+------------------------------------------------------------------+
void DetectInternalBreaks(const double &high[], const double &low[],
                          const double &close[], const datetime &time[],
                          int maxBar)
{
   if(g_intSwingHighCount < 2 || g_intSwingLowCount < 2)
      return;

   //--- Walk through internal swing points looking for breaks
   //--- These must be WITHIN the context of the external structure
   double lastIntHigh    = 0;
   int    lastIntHighBar = 0;
   double lastIntLow     = 999999;
   int    lastIntLowBar  = 0;

   //--- Process internal swing highs
   for(int i = 0; i < g_intSwingHighCount; i++)
   {
      if(lastIntHigh > 0 && g_intSwingHighs[i].price > lastIntHigh)
      {
         //--- Check it's not already an external break
         if(!IsExternalBreak(g_intSwingHighs[i].bar, lastIntHigh, true))
         {
            int breakBar = FindBreakBar(close, high, g_intSwingHighs[i].bar, lastIntHighBar, lastIntHigh, true);
            if(breakBar >= 0)
            {
               ENUM_BREAK_TYPE bType = (g_currentTrend == TREND_BULLISH) ? BREAK_BOS_BULL : BREAK_CHOCH_BULL;
               AddBreak(breakBar, lastIntHigh, bType, true, time[breakBar], g_intSwingHighs[i].price);
            }
         }
      }
      lastIntHigh    = g_intSwingHighs[i].price;
      lastIntHighBar = g_intSwingHighs[i].bar;
   }

   //--- Process internal swing lows
   for(int i = 0; i < g_intSwingLowCount; i++)
   {
      if(lastIntLow < 999999 && g_intSwingLows[i].price < lastIntLow)
      {
         if(!IsExternalBreak(g_intSwingLows[i].bar, lastIntLow, false))
         {
            int breakBar = FindBreakBar(close, low, g_intSwingLows[i].bar, lastIntLowBar, lastIntLow, false);
            if(breakBar >= 0)
            {
               ENUM_BREAK_TYPE bType = (g_currentTrend == TREND_BEARISH) ? BREAK_BOS_BEAR : BREAK_CHOCH_BEAR;
               AddBreak(breakBar, lastIntLow, bType, true, time[breakBar], g_intSwingLows[i].price);
            }
         }
      }
      lastIntLow    = g_intSwingLows[i].price;
      lastIntLowBar = g_intSwingLows[i].bar;
   }
}

//+------------------------------------------------------------------+
//| Check if a break coincides with an external break                  |
//+------------------------------------------------------------------+
bool IsExternalBreak(int bar, double price, bool isHigh)
{
   double tolerance = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;

   for(int i = 0; i < g_breakCount; i++)
   {
      if(!g_breaks[i].isInternal &&
         MathAbs(g_breaks[i].bar - bar) <= InpSwingStrength &&
         MathAbs(g_breaks[i].price - price) < tolerance)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Detect range zones (accumulation / distribution)                   |
//+------------------------------------------------------------------+
void DetectRangeZones(const double &high[], const double &low[],
                      const datetime &time[], int maxBar)
{
   g_rangeCount = 0;

   //--- Identify ranges where swing highs and lows are roughly equal
   //--- (price contained between levels for extended period)
   if(g_swingHighCount < 2 || g_swingLowCount < 2)
      return;

   double tolerance = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 50; // Price tolerance for "equal" levels

   //--- Walk through pairs of consecutive swing highs to find resistance clusters
   for(int i = 0; i < g_swingHighCount - 1; i++)
   {
      //--- Find matching swing lows that form a range with these highs
      double rangeHigh = g_swingHighs[i].price;
      double rangeLow  = 999999;
      int    startBar  = g_swingHighs[i].bar;
      int    endBar    = g_swingHighs[i + 1].bar;

      //--- Check if consecutive highs are at similar level (resistance cluster)
      if(MathAbs(g_swingHighs[i].price - g_swingHighs[i + 1].price) > tolerance * 3)
         continue;

      rangeHigh = MathMax(g_swingHighs[i].price, g_swingHighs[i + 1].price);

      //--- Find lows within this bar range
      for(int j = 0; j < g_swingLowCount; j++)
      {
         if(g_swingLows[j].bar <= startBar && g_swingLows[j].bar >= endBar)
         {
            if(g_swingLows[j].price < rangeLow)
               rangeLow = g_swingLows[j].price;
         }
      }

      if(rangeLow >= 999999) continue;

      //--- Validate: range width should be reasonable
      double rangeWidth = rangeHigh - rangeLow;
      double avgPrice   = (rangeHigh + rangeLow) / 2.0;

      if(rangeWidth <= 0) continue;

      //--- Range should be at least 3 bars wide and price contained
      int barSpan = startBar - endBar;
      if(barSpan < 3) continue;

      //--- Check range hasn't been broken (for endBar check)
      bool broken = false;
      for(int b = startBar; b >= endBar && b >= 0; b--)
      {
         if(high[b] > rangeHigh + tolerance || low[b] < rangeLow - tolerance)
         {
            broken = true;
            break;
         }
      }

      if(!broken)
      {
         int ridx = g_rangeCount;
         g_rangeCount++;
         ArrayResize(g_ranges, g_rangeCount);
         g_ranges[ridx].high      = rangeHigh;
         g_ranges[ridx].low       = rangeLow;
         g_ranges[ridx].startBar  = startBar;
         g_ranges[ridx].endBar    = endBar;
         g_ranges[ridx].startTime = time[startBar];
         g_ranges[ridx].endTime   = time[endBar];
         g_ranges[ridx].isActive  = (endBar <= InpSwingStrength + 2); // Still near current price
      }
   }
}

//+------------------------------------------------------------------+
//| Add a structure break to the array                                 |
//+------------------------------------------------------------------+
void AddBreak(int bar, double price, ENUM_BREAK_TYPE breakType,
              bool isInternal, datetime breakTime, double fromPrice)
{
   int idx = g_breakCount;
   g_breakCount++;
   ArrayResize(g_breaks, g_breakCount);
   g_breaks[idx].bar       = bar;
   g_breaks[idx].price     = price;
   g_breaks[idx].breakType = breakType;
   g_breaks[idx].isInternal = isInternal;
   g_breaks[idx].time      = breakTime;
   g_breaks[idx].fromPrice = fromPrice;
}

//+------------------------------------------------------------------+
//| Sort swing points by bar index (descending = oldest first)         |
//+------------------------------------------------------------------+
void SortSwingsByBar(SwingPoint &arr[], int count)
{
   //--- Simple bubble sort (data set is small)
   for(int i = 0; i < count - 1; i++)
   {
      for(int j = 0; j < count - i - 1; j++)
      {
         if(arr[j].bar < arr[j + 1].bar) // Higher bar = older in series
         {
            SwingPoint temp = arr[j];
            arr[j]     = arr[j + 1];
            arr[j + 1] = temp;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw all visual objects on the chart                                |
//+------------------------------------------------------------------+
void DrawAllObjects(const double &high[], const double &low[],
                    const datetime &time[])
{
   //--- Draw horizontal levels at swing points
   if(InpShowLevels)
   {
      DrawSwingLevels(time);
   }

   //--- Draw swing point labels (HH/HL/LH/LL)
   if(InpShowSwingLabels)
   {
      DrawSwingLabels(time);
   }

   //--- Draw BOS / CHoCH labels
   DrawStructureBreaks(time, high, low);

   //--- Draw range zones
   if(InpShowRangeZones)
   {
      DrawRangeZones(time);
   }

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw HH/HL/LH/LL labels on swing points                           |
//+------------------------------------------------------------------+
void DrawSwingLabels(const datetime &time[])
{
   //--- Draw swing high labels
   for(int i = 0; i < g_swingHighCount; i++)
   {
      string label = "";
      color  clr   = clrWhite;

      switch(g_swingHighs[i].structType)
      {
         case STRUCT_HH: label = "HH"; clr = InpHHColor; break;
         case STRUCT_LH: label = "LH"; clr = InpLHColor; break;
         default: label = "SH"; clr = clrGray; break;
      }

      string name = g_objPrefix + "SH_" + IntegerToString(i);
      DrawLabel(name, g_swingHighs[i].time, g_swingHighs[i].price,
                label, clr, true, InpFontSize);
   }

   //--- Draw swing low labels
   for(int i = 0; i < g_swingLowCount; i++)
   {
      string label = "";
      color  clr   = clrWhite;

      switch(g_swingLows[i].structType)
      {
         case STRUCT_HL: label = "HL"; clr = InpHLColor; break;
         case STRUCT_LL: label = "LL"; clr = InpLLColor; break;
         default: label = "SL"; clr = clrGray; break;
      }

      string name = g_objPrefix + "SL_" + IntegerToString(i);
      DrawLabel(name, g_swingLows[i].time, g_swingLows[i].price,
                label, clr, false, InpFontSize);
   }
}

//+------------------------------------------------------------------+
//| Draw horizontal levels extending N bars from each swing point      |
//+------------------------------------------------------------------+
void DrawSwingLevels(const datetime &time[])
{
   int totalBars = ArraySize(time);

   //--- Draw horizontal level from each swing high
   for(int i = 0; i < g_swingHighCount; i++)
   {
      int startBar = g_swingHighs[i].bar;
      int endBar   = MathMax(startBar - InpLevelBars, 0);

      //--- Clamp to array bounds
      if(startBar >= totalBars) startBar = totalBars - 1;
      if(endBar >= totalBars)   endBar = totalBars - 1;

      bool isBullish = (g_swingHighs[i].structType == STRUCT_HH);
      color clr   = isBullish ? InpBullLevelColor : InpBearLevelColor;
      ENUM_LINE_STYLE style = STYLE_SOLID;

      string name = g_objPrefix + "LH_" + IntegerToString(i);
      DrawHorizontalLine(name, time[startBar], time[endBar],
                        g_swingHighs[i].price, clr, InpLevelWidth, style);
   }

   //--- Draw horizontal level from each swing low
   for(int i = 0; i < g_swingLowCount; i++)
   {
      int startBar = g_swingLows[i].bar;
      int endBar   = MathMax(startBar - InpLevelBars, 0);

      //--- Clamp to array bounds
      if(startBar >= totalBars) startBar = totalBars - 1;
      if(endBar >= totalBars)   endBar = totalBars - 1;

      bool isBullish = (g_swingLows[i].structType == STRUCT_HL);
      color clr   = isBullish ? InpBullLevelColor : InpBearLevelColor;
      ENUM_LINE_STYLE style = STYLE_SOLID;

      string name = g_objPrefix + "LL_" + IntegerToString(i);
      DrawHorizontalLine(name, time[startBar], time[endBar],
                        g_swingLows[i].price, clr, InpLevelWidth, style);
   }
}

//+------------------------------------------------------------------+
//| Draw BOS / CHoCH break labels (clean, minimal)                     |
//+------------------------------------------------------------------+
void DrawStructureBreaks(const datetime &time[], const double &high[],
                         const double &low[])
{
   int totalBars = ArraySize(time);

   for(int i = 0; i < g_breakCount; i++)
   {
      StructureBreak brk = g_breaks[i];
      string label = "";
      color  clr   = clrWhite;
      bool   show  = false;

      //--- Determine label text and color
      if(brk.isInternal)
      {
         if(!InpShowInternalBreaks) continue;

         switch(brk.breakType)
         {
            case BREAK_BOS_BULL:   label = "iBOS"; break;
            case BREAK_BOS_BEAR:   label = "iBOS"; break;
            case BREAK_CHOCH_BULL: label = "iCHoCH"; break;
            case BREAK_CHOCH_BEAR: label = "iCHoCH"; break;
            default: continue;
         }
         clr = InpInternalColor;
         show = true;
      }
      else
      {
         switch(brk.breakType)
         {
            case BREAK_BOS_BULL:
               label = "BOS";
               clr   = InpBOSColor;
               show  = InpShowBOS;
               break;
            case BREAK_BOS_BEAR:
               label = "BOS";
               clr   = InpBOSColor;
               show  = InpShowBOS;
               break;
            case BREAK_CHOCH_BULL:
               label = "CHoCH";
               clr   = InpCHoCHColor;
               show  = InpShowCHoCH;
               break;
            case BREAK_CHOCH_BEAR:
               label = "CHoCH";
               clr   = InpCHoCHColor;
               show  = InpShowCHoCH;
               break;
            default:
               continue;
         }
      }

      if(!show) continue;

      //--- Draw dashed break level line (same length as swing levels)
      string lineName = g_objPrefix + "BRK_L_" + IntegerToString(i);
      int lineEndBar = MathMax(brk.bar - InpLevelBars, 0);
      if(lineEndBar < totalBars && brk.bar < totalBars)
      {
         DrawHorizontalLine(lineName, time[brk.bar], time[lineEndBar], brk.price,
                           clr, 1, STYLE_DASH);
      }

      //--- Draw the label at the midpoint of the break line
      string labelName = g_objPrefix + "BRK_" + IntegerToString(i);
      bool isBull = (brk.breakType == BREAK_BOS_BULL || brk.breakType == BREAK_CHOCH_BULL);
      int labelBar = MathMax(brk.bar - (InpLevelBars / 2), 0);
      if(labelBar >= totalBars) labelBar = totalBars - 1;

      DrawLabel(labelName, time[labelBar], brk.price, label, clr, isBull,
                brk.isInternal ? InpFontSize - 1 : InpFontSize);
   }
}

//+------------------------------------------------------------------+
//| Draw range zones as rectangles                                     |
//+------------------------------------------------------------------+
void DrawRangeZones(const datetime &time[])
{
   for(int i = 0; i < g_rangeCount; i++)
   {
      string name = g_objPrefix + "RNG_" + IntegerToString(i);

      //--- Draw rectangle for range zone
      if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0,
                       g_ranges[i].startTime, g_ranges[i].high,
                       g_ranges[i].endTime, g_ranges[i].low))
         continue;

      ObjectSetInteger(0, name, OBJPROP_COLOR, InpRangeColor);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

      //--- Range labels (Range H / Range L)
      string rhName = g_objPrefix + "RH_" + IntegerToString(i);
      string rlName = g_objPrefix + "RL_" + IntegerToString(i);

      DrawLabel(rhName, g_ranges[i].startTime, g_ranges[i].high,
                "Range H", InpRangeColor, true, InpFontSize - 1);
      DrawLabel(rlName, g_ranges[i].startTime, g_ranges[i].low,
                "Range L", InpRangeColor, false, InpFontSize - 1);
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
   g_intSwingHighCount = 0;
   g_intSwingLowCount  = 0;
   g_breakCount        = 0;
   g_rangeCount        = 0;

   ArrayResize(g_swingHighs, 0);
   ArrayResize(g_swingLows, 0);
   ArrayResize(g_intSwingHighs, 0);
   ArrayResize(g_intSwingLows, 0);
   ArrayResize(g_breaks, 0);
   ArrayResize(g_ranges, 0);
}
//+------------------------------------------------------------------+
