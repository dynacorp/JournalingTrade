//+------------------------------------------------------------------+
//| PAM/Context.mqh  —  Shared types, structs, and central context  |
//| Price Action Mentor AI  v1.0                                    |
//+------------------------------------------------------------------+
#ifndef PAM_CONTEXT_MQH
#define PAM_CONTEXT_MQH

//--- Trend direction
enum ETrend
{
   TREND_UNDEFINED = 0,
   TREND_BULLISH,
   TREND_BEARISH,
   TREND_RANGING
};

//--- Market phase
enum EPhase
{
   PHASE_UNDEFINED     = 0,
   PHASE_ACCUMULATION,    // Low volatility, range-bound, load phase
   PHASE_MANIPULATION,    // Spike outside range to hunt stops
   PHASE_EXPANSION,       // Strong directional move, BOS sequence
   PHASE_DISTRIBUTION,    // Momentum weakening at top/bottom
   PHASE_COMPRESSION,     // ATR contracting, pre-breakout coiling
   PHASE_CORRECTIVE,      // Pullback within a larger trend
   PHASE_TRENDING         // Healthy HH/HL or LH/LL sequence
};

//--- Education depth
enum EMode
{
   MODE_BEGINNER      = 0,   // Plain-English concepts
   MODE_ADVANCED      = 1,   // Technical price action terms
   MODE_INSTITUTIONAL = 2    // Order flow + market maker logic
};

//--- Candle personality
enum ECandleType
{
   CANDLE_NEUTRAL          = 0,
   CANDLE_BULL_STRONG,         // Large body bull, small wicks
   CANDLE_BEAR_STRONG,         // Large body bear, small wicks
   CANDLE_DISPLACEMENT_BULL,   // Expansion bull breaking structure
   CANDLE_DISPLACEMENT_BEAR,   // Expansion bear breaking structure
   CANDLE_EXHAUSTION_BULL,     // Large upper wick, tiny body — bull rejection
   CANDLE_EXHAUSTION_BEAR,     // Large lower wick, tiny body — bear rejection
   CANDLE_INDECISION,          // Doji / spinning top
   CANDLE_HAMMER,              // Lower wick dominant at potential low
   CANDLE_SHOOTING_STAR,       // Upper wick dominant at potential high
   CANDLE_COMPRESSION          // Very small range — market coiling
};

//--- Structure event type
enum EStructureEvent
{
   SE_NONE      = 0,
   SE_HH,          // Higher High
   SE_HL,          // Higher Low
   SE_LH,          // Lower High
   SE_LL,          // Lower Low
   SE_BOS_BULL,    // Bullish Break of Structure
   SE_BOS_BEAR,    // Bearish Break of Structure
   SE_CHOCH_BULL,  // Change of Character — bullish reversal
   SE_CHOCH_BEAR,  // Change of Character — bearish reversal
   SE_MSS_BULL,    // Market Structure Shift with momentum — bullish
   SE_MSS_BEAR     // Market Structure Shift with momentum — bearish
};

//--- Liquidity level type
enum ELiqType
{
   LIQ_BUY_SIDE  = 0,   // Equal highs / prior highs — stops resting above
   LIQ_SELL_SIDE         // Equal lows  / prior lows  — stops resting below
};

//--- Smart zone type
enum EZoneType
{
   ZONE_OB_BULL     = 0,
   ZONE_OB_BEAR,
   ZONE_FVG_BULL,
   ZONE_FVG_BEAR,
   ZONE_BREAKER_BULL,
   ZONE_BREAKER_BEAR
};

//--- Array size limits
#define PAM_MAX_SWINGS   80
#define PAM_MAX_LIQ      40
#define PAM_MAX_ZONES    32
#define PAM_MAX_CANDLES  30

//+------------------------------------------------------------------+
struct SSwing
{
   int             bar;      // series index (0 = newest)
   datetime        time;
   double          price;
   bool            isHigh;
   EStructureEvent label;    // HH/HL/LH/LL
   bool            isBOS;
   bool            isCHoCH;
   bool            isMSS;
};

//+------------------------------------------------------------------+
struct SLiqLevel
{
   double   price;
   datetime timeLeft;      // bar where the level was formed
   ELiqType type;
   bool     swept;
   datetime sweepTime;
   int      strength;      // 1–5, counts clustered touches
};

//+------------------------------------------------------------------+
struct SZone
{
   EZoneType type;
   double    top;
   double    bot;
   datetime  timeStart;
   bool      mitigated;    // price traded into zone by >= 50%
   int       strength;     // 1–5
};

//+------------------------------------------------------------------+
struct SCandle
{
   int         bar;
   datetime    time;
   ECandleType type;
   double      bodyRatio;       // body / total_range
   double      upperWickRatio;  // upper_wick / total_range
   double      lowerWickRatio;  // lower_wick / total_range
   double      rangeVsAtr;      // total_range / ATR
   string      label;
   color       col;
   bool        showLabel;
};

//+------------------------------------------------------------------+
struct SScore
{
   double structure;    // 0–100
   double liquidity;    // 0–100
   double momentum;     // 0–100
   double imbalance;    // 0–100
   double conviction;   // 0–100
   double total;        // weighted composite 0–100
};

//+------------------------------------------------------------------+
//| Central shared context — single global instance                  |
//+------------------------------------------------------------------+
struct SPAMContext
{
   //--- Configuration (populated from inputs in OnInit)
   EMode           mode;
   int             pivStr;
   int             lookback;
   ENUM_TIMEFRAMES htf;
   bool            showInternal;
   bool            showBOS;
   bool            showCHoCH;
   bool            showLiq;
   bool            showSweeps;
   bool            showOB;
   bool            showFVG;
   bool            showBreaker;
   bool            showCandles;
   double          eqTol;          // ATR multiplier for equal-level clustering
   double          minFvgAtr;      // Min FVG height in ATR units
   double          dispThresh;     // Displacement: body > X * ATR
   color           bullCol;
   color           bearCol;
   color           neutCol;
   color           liqCol;
   color           fvgBullCol;
   color           fvgBearCol;
   color           obBullCol;
   color           obBearCol;

   //--- ATR handles
   int    atrHandle;
   int    htfAtrHandle;
   double atr;           // current bar ATR value
   double atrHtf;

   //--- Current market state
   ETrend trend;
   ETrend htfTrend;
   EPhase phase;

   //--- Swing points (sorted oldest to newest by bar index)
   SSwing  swings[PAM_MAX_SWINGS];
   int     nSwings;

   //--- Last confirmed swing boundary prices (for BOS/CHoCH)
   double   lastSwH;       // last confirmed swing-high price
   double   lastSwL;       // last confirmed swing-low price
   double   prevSwH;       // second-to-last swing high
   double   prevSwL;       // second-to-last swing low
   datetime lastSwHTime;
   datetime lastSwLTime;

   //--- Liquidity levels
   SLiqLevel liq[PAM_MAX_LIQ];
   int       nLiq;

   //--- Smart zones
   SZone  zones[PAM_MAX_ZONES];
   int    nZones;

   //--- Candle analysis (most recent PAM_MAX_CANDLES bars)
   SCandle candles[PAM_MAX_CANDLES];
   int     nCandles;

   //--- Educational score
   SScore score;
   string narrative;

   //--- Helper flags populated by engines (consumed by scoring/UI)
   bool hasBullBOS;
   bool hasBearBOS;
   bool hasBullCHoCH;
   bool hasBearCHoCH;
   bool hasBullMSS;
   bool hasBearMSS;
   bool liqSweptBull;    // sell-side liquidity swept recently (bullish)
   bool liqSweptBear;    // buy-side liquidity swept recently (bearish)
   bool hasBullOB;
   bool hasBearOB;
   bool hasBullFVG;
   bool hasBearFVG;
   bool hasBullBreaker;
   bool hasBearBreaker;
   bool dispBullRecent;  // displacement bull candle in last 5 bars
   bool dispBearRecent;
   bool exhaustBullRecent;
   bool exhaustBearRecent;

   //--- v1.1: Internal structure (micro pivots inside the larger swing)
   SSwing  iSwings[PAM_MAX_SWINGS];
   int     nISwings;

   //--- v1.1: Premium / Discount
   bool   showPremDisc;
   double equilPrice;     // midpoint of last major swing range
   double premDiscPct;    // 0=at lastSwL, 100=at lastSwH, 50=equilibrium

   //--- v1.1: Session shading
   bool   showSessions;
   bool   showAsian;
   bool   showLondon;
   bool   showNY;
   bool   showOverlap;
   int    asianOpenH;     // broker-time hours (default 22)
   int    asianCloseH;    // default 7 (next day)
   int    londonOpenH;    // default 7
   int    londonCloseH;   // default 16
   int    nyOpenH;        // default 12
   int    nyCloseH;       // default 21
   int    sessDays;       // how many calendar days of sessions to draw

   //--- v1.2: Kill Zones
   bool   showKillZones;
   bool   showLondonKZ;   // 07:00–10:00
   bool   showNYAMKZ;     // 12:00–15:00
   bool   showNYPMKZ;     // 19:00–21:00
   bool   showAsianKZ;    // 20:00–23:00
   int    kzDays;         // calendar days to draw

   //--- v1.2: Draw on Liquidity
   bool   showDOL;
   double dolUp;          // nearest unswept BSL above price (0 = none)
   double dolDown;        // nearest unswept SSL below price (0 = none)

   //--- v1.3: Daily / Weekly Bias
   bool   showDailyBias;
   bool   showPDLevels;   // draw PDH / PDL / PDC / PDM lines
   bool   showWeeklyOpen; // draw weekly open line
   double pdHigh;         // previous day's high
   double pdLow;          // previous day's low
   double pdClose;        // previous day's close
   double pdMid;          // previous day's midpoint
   double weeklyOpen;     // current week's opening price
   ETrend dailyBias;      // BULLISH=above PDH, BEARISH=below PDL, RANGING=inside
   ETrend weeklyBias;     // BULLISH=above weekly open, BEARISH=below

   //--- v1.4: Setup Pattern Markers
   bool   showJudas;        // Judas Swing detector
   bool   showSilverBullet; // Silver Bullet time windows
   bool   showCISD;         // Change in State of Delivery
   bool   showOTE;          // Optimal Trade Entry zone
   int    sbAMOpenH;        // Silver Bullet AM window open  (default 10)
   int    sbAMCloseH;       // Silver Bullet AM window close (default 11)
   int    sbPMOpenH;        // Silver Bullet PM window open  (default 14)
   int    sbPMCloseH;       // Silver Bullet PM window close (default 15)
   string activeSetup;      // current dominant setup label for dashboard

   //--- v1.5: Trade Management Helper
   bool   showTradeManager; // enable SL/TP/RR overlay
   double suggestedSL;      // structure-based stop loss level (0 = none)
   double suggestedTP;      // DOL-based take profit level (0 = none)
   double setupRR;          // reward:risk ratio (0 = invalid)
   bool   isBullSetup;      // true = long bias, false = short bias

   //--- Display mode
   bool   outlineMode;      // if true: all filled boxes rendered as dotted outlines only
};

#endif // PAM_CONTEXT_MQH
