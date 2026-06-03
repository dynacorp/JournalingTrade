//+------------------------------------------------------------------+
//| PAM/UIEngine.mqh  —  Dashboard, labels, and visual management  |
//|                                                                  |
//| Dashboard layout (top-left corner):                              |
//|  ┌─────────────────────────────────────────────────┐            |
//|  │  PRICE ACTION MENTOR AI         [MODE]           │            |
//|  ├────────────────┬────────────────────────────────┤            |
//|  │  Symbol / TF   │  Structure                     │            |
//|  │  HTF Bias      │  Phase                         │            |
//|  │  Candle        │  Liquidity                     │            |
//|  ├────────────────┴────────────────────────────────┤            |
//|  │  SCORE  ▓▓▓▓▓▓▓░░░  72%                        │            |
//|  ├─────────────────────────────────────────────────┤            |
//|  │  Narrative text (wraps to 3 display lines)      │            |
//|  └─────────────────────────────────────────────────┘            |
//+------------------------------------------------------------------+
#ifndef PAM_UI_MQH
#define PAM_UI_MQH
#include "Context.mqh"

// Dashboard geometry
#define UI_X        8
#define UI_Y        28
#define UI_W        310
#define UI_H        444
#define UI_LPAD     16
#define UI_FONT     "Consolas"
#define UI_FSIZE    8
#define UI_FSIZE_T  9
#define UI_BG       C'8,8,18'
#define UI_BORDER   C'45,45,90'
#define UI_TITLE    clrDodgerBlue
#define UI_SILVER   clrSilver

//+------------------------------------------------------------------+
// Internal label creation helper
//+------------------------------------------------------------------+
void UI_MakeLabel(string name, int x, int y, int sz = UI_FSIZE)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        UI_SILVER);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,     sz);
   ObjectSetString(0,  name, OBJPROP_FONT,         UI_FONT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, name, OBJPROP_BACK,         false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,       3);
}

void UI_SetLabel(string name, string text, color c)
{
   ObjectSetString(0,  name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
}

// Helper for repeated character string (must be before CreateDash)
string StringRepeat(const string &ch, int count)
{
   string r = "";
   for(int i = 0; i < count; i++) r += ch;
   return r;
}

//+------------------------------------------------------------------+
// UIEngine_CreateDash
//   One-time creation of all dashboard skeleton objects.
//+------------------------------------------------------------------+
void UIEngine_CreateDash(const string &pfx)
{
   // Background panel
   string bg = pfx + "BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE,   UI_X);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE,   UI_Y);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE,       UI_W);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE,       UI_H);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,     UI_BG);
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR,       UI_BORDER);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, bg, OBJPROP_BACK,        false);
   ObjectSetInteger(0, bg, OBJPROP_ZORDER,      1);

   int row = UI_Y + 10;
   int dx  = UI_X + UI_LPAD;

   UI_MakeLabel(pfx + "TITLE",   dx,     row,        UI_FSIZE_T);
   UI_MakeLabel(pfx + "DIVIDER", dx,     row += 20,  UI_FSIZE);
   UI_MakeLabel(pfx + "SYMBOL",  dx,     row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "STRUCT",  dx,     row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "HTF",     dx,     row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "PHASE",   dx,     row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "CANDLE",  dx,     row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "LIQ",     dx,     row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "DIVIDER2",dx,     row += 16,  UI_FSIZE);
   UI_MakeLabel(pfx + "SCORE_T", dx,     row += 13,  UI_FSIZE);
   UI_MakeLabel(pfx + "SC_STR",  dx,     row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "SC_LIQ",  dx,     row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "SC_MOM",  dx,     row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "SC_IMB",  dx,     row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "SC_CVN",  dx,     row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "SC_TOT",  dx,     row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "DIVIDER3",dx,     row += 16,  UI_FSIZE);
   UI_MakeLabel(pfx + "NAR1",    dx,     row += 13,  7);
   UI_MakeLabel(pfx + "NAR2",    dx,     row += 12,  7);
   UI_MakeLabel(pfx + "NAR3",    dx,     row += 12,  7);
   UI_MakeLabel(pfx + "NAR4",    dx,     row += 12,  7);
   UI_MakeLabel(pfx + "DIVIDER4",dx,     row += 16,  UI_FSIZE);
   UI_MakeLabel(pfx + "SESS",    dx,     row += 13,  UI_FSIZE);
   UI_MakeLabel(pfx + "PREMDISC",dx,     row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "KILLZONE", dx,    row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "DOL",      dx,    row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "DBIAS",    dx,    row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "SETUP",    dx,    row += 14,  UI_FSIZE);
   UI_MakeLabel(pfx + "TMGR",     dx,    row += 14,  UI_FSIZE);

   ObjectSetString(0, pfx + "TITLE",    OBJPROP_TEXT, "  PRICE ACTION MENTOR AI");
   ObjectSetInteger(0,pfx + "TITLE",    OBJPROP_COLOR, UI_TITLE);
   ObjectSetString(0, pfx + "DIVIDER",  OBJPROP_TEXT, StringRepeat("─", 42));
   ObjectSetString(0, pfx + "DIVIDER2", OBJPROP_TEXT, StringRepeat("─", 42));
   ObjectSetString(0, pfx + "DIVIDER3", OBJPROP_TEXT, StringRepeat("─", 42));
   ObjectSetString(0, pfx + "DIVIDER4", OBJPROP_TEXT, StringRepeat("─", 42));
   ObjectSetString(0, pfx + "SCORE_T",  OBJPROP_TEXT, "  EDUCATIONAL QUALITY SCORE");
}

//+------------------------------------------------------------------+
// Score bar: "▓▓▓▓▓▓░░░░  60%"
//+------------------------------------------------------------------+
string ScoreBar(double v, int barLen = 10)
{
   int filled = (int)MathRound(v / 100.0 * barLen);
   string bar = "";
   for(int i = 0; i < barLen; i++) bar += (i < filled) ? "▓" : "░";
   return bar + "  " + IntegerToString((int)MathRound(v)) + "%";
}

color ScoreColor(double v)
{
   if(v >= 75) return C'0,200,80';
   if(v >= 50) return C'200,160,0';
   return C'200,60,60';
}

//+------------------------------------------------------------------+
// UIEngine_UpdateDash
//   Called each new bar to refresh all dashboard text.
//+------------------------------------------------------------------+
void UIEngine_UpdateDash(const SPAMContext &ctx, double curPrice, const string &pfx)
{
   string modeTxt;
   color  modeCol;
   switch(ctx.mode)
   {
      case MODE_BEGINNER:      modeTxt = "[BEGINNER]";      modeCol = C'80,180,255'; break;
      case MODE_ADVANCED:      modeTxt = "[ADVANCED]";      modeCol = C'255,200,0';  break;
      case MODE_INSTITUTIONAL: modeTxt = "[INSTITUTIONAL]"; modeCol = C'255,100,200';break;
      default:                 modeTxt = "";                modeCol = UI_SILVER;     break;
   }

   // Symbol + TF + mode
   string tfStr = EnumToString(_Period);
   StringReplace(tfStr, "PERIOD_", "");
   UI_SetLabel(pfx + "SYMBOL",
               "  " + _Symbol + "  " + tfStr + "  " + modeTxt, modeCol);

   // Structure
   string structTxt = "";
   color  structCol = UI_SILVER;
   switch(ctx.trend)
   {
      case TREND_BULLISH:
         structTxt = "  Structure  BULLISH ▲";
         structCol  = ctx.bullCol;
         if(ctx.hasBullMSS)   structTxt += "  MSS";
         else if(ctx.hasBullCHoCH) structTxt += "  CHoCH";
         else if(ctx.hasBullBOS)   structTxt += "  BOS";
         break;
      case TREND_BEARISH:
         structTxt = "  Structure  BEARISH ▼";
         structCol  = ctx.bearCol;
         if(ctx.hasBearMSS)   structTxt += "  MSS";
         else if(ctx.hasBearCHoCH) structTxt += "  CHoCH";
         else if(ctx.hasBearBOS)   structTxt += "  BOS";
         break;
      case TREND_RANGING:
         structTxt = "  Structure  RANGING ~";
         structCol  = C'200,180,0';
         break;
      default:
         structTxt = "  Structure  Forming...";
         structCol  = C'100,100,100';
         break;
   }
   UI_SetLabel(pfx + "STRUCT", structTxt, structCol);

   // HTF bias
   string htfStr = "  HTF Bias   ";
   color  htfCol  = UI_SILVER;
   switch(ctx.htfTrend)
   {
      case TREND_BULLISH:
         htfStr += "BULLISH ▲";
         htfCol  = (ctx.trend == TREND_BULLISH) ? ctx.bullCol : C'0,120,80';
         if(ctx.trend == TREND_BULLISH) htfStr += "  ✓ Aligned";
         else                           htfStr += "  ✗ Diverge";
         break;
      case TREND_BEARISH:
         htfStr += "BEARISH ▼";
         htfCol  = (ctx.trend == TREND_BEARISH) ? ctx.bearCol : C'120,40,0';
         if(ctx.trend == TREND_BEARISH) htfStr += "  ✓ Aligned";
         else                           htfStr += "  ✗ Diverge";
         break;
      case TREND_RANGING:  htfStr += "RANGING ~"; htfCol = C'160,140,0'; break;
      default:             htfStr += "---"; break;
   }
   UI_SetLabel(pfx + "HTF", htfStr, htfCol);

   // Phase
   string phaseStr = "  Phase      ";
   color  phaseCol  = UI_SILVER;
   switch(ctx.phase)
   {
      case PHASE_EXPANSION:   phaseStr += "EXPANSION ↗";    phaseCol = ctx.bullCol; break;
      case PHASE_COMPRESSION: phaseStr += "COMPRESSION ◆";  phaseCol = C'200,180,0'; break;
      case PHASE_CORRECTIVE:  phaseStr += "CORRECTIVE ↘";   phaseCol = C'150,150,200'; break;
      case PHASE_ACCUMULATION:phaseStr += "ACCUMULATION ▭"; phaseCol = C'0,150,200'; break;
      case PHASE_MANIPULATION:phaseStr += "MANIPULATION ⚡"; phaseCol = C'255,100,0'; break;
      case PHASE_DISTRIBUTION:phaseStr += "DISTRIBUTION ↙"; phaseCol = ctx.bearCol; break;
      case PHASE_TRENDING:    phaseStr += "TRENDING →";      phaseCol = ctx.bullCol; break;
      default:                phaseStr += "---"; break;
   }
   UI_SetLabel(pfx + "PHASE", phaseStr, phaseCol);

   // Current candle
   string candleTxt = "  Candle     ";
   color  candleCol  = UI_SILVER;
   if(ctx.nCandles > 0)
   {
      SCandle c0 = ctx.candles[0];
      candleTxt += CandleEngine_TypeString(c0.type);
      candleCol  = c0.col;
   }
   else candleTxt += "---";
   UI_SetLabel(pfx + "CANDLE", candleTxt, candleCol);

   // Liquidity
   int bsl = 0, ssl = 0, swept = 0;
   for(int i = 0; i < ctx.nLiq; i++)
   {
      if(ctx.liq[i].swept)                          swept++;
      else if(ctx.liq[i].type == LIQ_BUY_SIDE)     bsl++;
      else                                          ssl++;
   }
   string liqTxt = StringFormat("  Liquidity  BSL:%d  SSL:%d  Swept:%d", bsl, ssl, swept);
   color  liqCol  = (bsl > 0 || ssl > 0) ? ctx.liqCol : C'80,80,80';
   UI_SetLabel(pfx + "LIQ", liqTxt, liqCol);

   // Score bars
   SScore s = ctx.score;
   UI_SetLabel(pfx + "SC_STR", "  Structure  " + ScoreBar(s.structure), ScoreColor(s.structure));
   UI_SetLabel(pfx + "SC_LIQ", "  Liquidity  " + ScoreBar(s.liquidity), ScoreColor(s.liquidity));
   UI_SetLabel(pfx + "SC_MOM", "  Momentum   " + ScoreBar(s.momentum),  ScoreColor(s.momentum));
   UI_SetLabel(pfx + "SC_IMB", "  Imbalance  " + ScoreBar(s.imbalance), ScoreColor(s.imbalance));
   UI_SetLabel(pfx + "SC_CVN", "  Conviction " + ScoreBar(s.conviction),ScoreColor(s.conviction));
   UI_SetLabel(pfx + "SC_TOT",
               "  ── TOTAL   " + ScoreBar(s.total) + " ──",
               ScoreColor(s.total));

   // Narrative — split into 4 display lines of ~50 chars each
   string nar = ctx.narrative;
   string narLines[4];
   narLines[0] = narLines[1] = narLines[2] = narLines[3] = "";
   int  lineMaxLen = 48;
   int  pos = 0;
   for(int i = 0; i < 4 && pos < StringLen(nar); i++)
   {
      int end = pos + lineMaxLen;
      if(end >= StringLen(nar)) end = StringLen(nar);
      else
      {
         // Try to break at word boundary
         while(end > pos && StringGetCharacter(nar, end) != 32 && StringGetCharacter(nar, end) != 124) end--;
         if(end == pos) end = pos + lineMaxLen;
      }
      narLines[i] = "  " + StringSubstr(nar, pos, end - pos);
      pos = end + 1;
   }
   UI_SetLabel(pfx + "NAR1", narLines[0], C'180,180,220');
   UI_SetLabel(pfx + "NAR2", narLines[1], C'160,160,200');
   UI_SetLabel(pfx + "NAR3", narLines[2], C'140,140,180');
   UI_SetLabel(pfx + "NAR4", narLines[3], C'120,120,160');

   // Session + Premium/Discount (v1.1)
   UI_SetLabel(pfx + "SESS",     SessionEngine_CurrentString(ctx),              C'140,160,210');
   UI_SetLabel(pfx + "PREMDISC", PremDiscEngine_PositionString(ctx, ctx.mode),  C'200,180,130');

   // Kill Zone + Draw on Liquidity (v1.2)
   color kzCol = (KillZoneEngine_IsActive(ctx)) ? C'240,210,0' : C'100,100,100';
   UI_SetLabel(pfx + "KILLZONE", KillZoneEngine_CurrentString(ctx), kzCol);
   UI_SetLabel(pfx + "DOL",      DOLEngine_DashString(ctx, curPrice), C'220,160,60');

   // Daily / Weekly Bias (v1.3)
   color dbiasCol = C'180,180,180';
   if(ctx.dailyBias == TREND_BULLISH)      dbiasCol = C'0,200,120';
   else if(ctx.dailyBias == TREND_BEARISH) dbiasCol = C'200,80,80';
   else if(ctx.dailyBias == TREND_RANGING) dbiasCol = C'180,160,0';
   UI_SetLabel(pfx + "DBIAS", DailyBiasEngine_DashString(ctx, curPrice, ctx.mode), dbiasCol);

   // Setup Pattern Markers (v1.4)
   color setupCol = (ctx.activeSetup != "") ? C'255,210,60' : C'80,80,80';
   UI_SetLabel(pfx + "SETUP", SetupEngine_ActiveSetupString(ctx), setupCol);

   // Trade Management Helper (v1.5)
   color tmgrCol = C'100,100,100';
   if(ctx.showTradeManager && ctx.setupRR > 0)
   {
      if(ctx.setupRR >= 2.0)      tmgrCol = C'0,220,120';
      else if(ctx.setupRR >= 1.0) tmgrCol = C'220,180,0';
      else                        tmgrCol = C'200,80,80';
   }
   UI_SetLabel(pfx + "TMGR", TradeManagerEngine_DashString(ctx), tmgrCol);
}

//+------------------------------------------------------------------+
// UIEngine_DeleteObjects — delete all non-dashboard objects
//+------------------------------------------------------------------+
void UIEngine_DeleteObjects(const string &pfx)
{
   // Keys that are part of the dashboard — keep these
   string keep[] = {
      "BG","TITLE","DIVIDER","DIVIDER2","DIVIDER3","DIVIDER4",
      "SYMBOL","STRUCT","HTF","PHASE","CANDLE","LIQ",
      "SCORE_T","SC_STR","SC_LIQ","SC_MOM","SC_IMB","SC_CVN","SC_TOT",
      "NAR1","NAR2","NAR3","NAR4",
      "SESS","PREMDISC","KILLZONE","DOL","DBIAS","SETUP","TMGR",
      "REPLAY_BG","REPLAY_TITLE","REPLAY_L1","REPLAY_L2",
      "REPLAY_L3","REPLAY_L4","REPLAY_L5","REPLAY_N1","REPLAY_N2","REPLAY_N3"
   };
   int keepN = ArraySize(keep);

   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, 0, -1);
      if(StringFind(nm, pfx) != 0) continue;
      bool isDash = false;
      for(int d = 0; d < keepN; d++)
         if(nm == pfx + keep[d]) { isDash = true; break; }
      if(!isDash) ObjectDelete(0, nm);
   }
}

void UIEngine_DeleteAllObjects(const string &pfx)
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, 0, -1);
      if(StringFind(nm, pfx) == 0) ObjectDelete(0, nm);
   }
}

// Forward declarations for engines included after UIEngine.mqh in the main file
string CandleEngine_TypeString(ECandleType t);
string SessionEngine_CurrentString(const SPAMContext &ctx);
string PremDiscEngine_PositionString(const SPAMContext &ctx, EMode mode);
string KillZoneEngine_CurrentString(const SPAMContext &ctx);
bool   KillZoneEngine_IsActive(const SPAMContext &ctx);
string DOLEngine_DashString(const SPAMContext &ctx, double curPrice);
string DailyBiasEngine_DashString(const SPAMContext &ctx, double curPrice, EMode mode);
string SetupEngine_ActiveSetupString(const SPAMContext &ctx);
string TradeManagerEngine_DashString(const SPAMContext &ctx);

#endif // PAM_UI_MQH
