#ifndef __SMARTEDGE_UI_MQH__
#define __SMARTEDGE_UI_MQH__

//+------------------------------------------------------------------+
//|  SmartEdgeUI.mqh                                                 |
//|  On-chart panel UI for SmartEdge EA/Indicator                    |
//|  Reusable include — references globals defined in including file  |
//+------------------------------------------------------------------+

//--- Layout defines
#define UI_X           15
#define UI_Y           25
#define UI_W           278
#define UI_ROW         16
#define UI_SML         13
#define UI_BTN_H       20
#define UI_HDR_H       24
#define UI_SEC_GAP     4
#define UI_SEP_H       1
#define UI_FONT        "Consolas"
#define UI_SZ          8
#define UI_SZ_SM       7
#define UI_SZ_HDR      9
#define UI_COL1        (UI_X + 8)
#define UI_COL2        (UI_X + 128)
#define UI_COL3        (UI_X + 204)

//--- Color defines
#define UI_CLR_PANEL_BG   C'13,16,26'
#define UI_CLR_HDR_BG     C'28,33,52'
#define UI_CLR_SEP        C'38,42,62'
#define UI_CLR_TEXT       C'175,180,198'
#define UI_CLR_DIM        C'82,87,108'
#define UI_CLR_WHITE      clrWhite
#define UI_CLR_GOOD       C'72,210,72'
#define UI_CLR_MED        C'210,172,48'
#define UI_CLR_BAD        C'212,76,56'
#define UI_CLR_BUY        C'88,162,252'
#define UI_CLR_SELL       C'252,112,72'
#define UI_CLR_PEN        C'218,118,58'
#define UI_CLR_BTN_BUY_BG    C'11,48,74'
#define UI_CLR_BTN_SELL_BG   C'66,24,16'
#define UI_CLR_BTN_MARK_BG   C'18,42,64'
#define UI_CLR_BTN_MARKS_BG  C'58,20,14'
#define UI_CLR_BTN_CLR_BG    C'24,24,40'

//+------------------------------------------------------------------+
//|  Low-level helpers                                               |
//+------------------------------------------------------------------+

void UI_CreateRect(const string name, int x, int y, int w, int h, color bg)
{
    if(ObjectFind(0, name) < 0)
        ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
    ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
    ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bg);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, name, OBJPROP_COLOR,      bg);
    ObjectSetInteger(0, name, OBJPROP_BACK,       true);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

void UI_CreateLabel(const string name, int x, int y, const string text, color clr, int fsz = UI_SZ)
{
    if(ObjectFind(0, name) < 0)
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
    ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_BACK,       false);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
    ObjectSetString (0, name, OBJPROP_FONT,       UI_FONT);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   fsz);
    ObjectSetString (0, name, OBJPROP_TEXT,       text);
    ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
}

void UI_CreateButton(const string name, int x, int y, int w, int h,
                     const string text, color bg, color fg)
{
    if(ObjectFind(0, name) < 0)
        ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
    ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
    ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_BACK,       false);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
    ObjectSetInteger(0, name, OBJPROP_STATE,      false);
    ObjectSetString (0, name, OBJPROP_FONT,       UI_FONT);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   UI_SZ);
    ObjectSetString (0, name, OBJPROP_TEXT,       text);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bg);
    ObjectSetInteger(0, name, OBJPROP_COLOR,      fg);
}

void UI_SetText(const string name, const string text)
{
    if(ObjectFind(0, name) >= 0)
        ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void UI_SetColor(const string name, color clr)
{
    if(ObjectFind(0, name) >= 0)
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void UI_SetTextColor(const string name, const string text, color clr)
{
    if(ObjectFind(0, name) >= 0)
    {
        ObjectSetString (0, name, OBJPROP_TEXT,  text);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    }
}

//+------------------------------------------------------------------+
//|  Color logic helpers                                             |
//+------------------------------------------------------------------+

color ScoreColor(double score)
{
    if(score >= 65.0) return UI_CLR_GOOD;
    if(score >= 45.0) return UI_CLR_MED;
    return UI_CLR_BAD;
}

color ClassColor(const string cls)
{
    if(cls == "A+")   return UI_CLR_GOOD;
    if(cls == "Good") return UI_CLR_MED;
    if(cls == "Weak") return C'165,135,40';
    return UI_CLR_BAD;
}

color ExhaustionColor(double ex)
{
    if(ex < 30.0) return UI_CLR_GOOD;
    if(ex < 60.0) return UI_CLR_MED;
    return UI_CLR_BAD;
}

color ComponentColor(double val, int maxVal)
{
    if(maxVal <= 0) return UI_CLR_TEXT;
    double pct = val / (double)maxVal;
    if(pct >= 0.65) return UI_CLR_GOOD;
    if(pct >= 0.35) return UI_CLR_MED;
    return UI_CLR_BAD;
}

color HealthStateColor(ENUM_HEALTH_STATE state)
{
    switch(state)
    {
        case HEALTH_HEALTHY:              return UI_CLR_GOOD;
        case HEALTH_MILD_CAUTION:         return C'140,210,90';
        case HEALTH_MOMENTUM_WEAKENING:   return UI_CLR_MED;
        case HEALTH_EXHAUSTION_WATCH:     return C'210,140,48';
        case HEALTH_EXIT_WATCH:           return UI_CLR_BAD;
        case HEALTH_REVERSAL_CONFIRMED:   return C'240,60,60';
        default:                          return UI_CLR_DIM;
    }
}

color ExhaustionComponentColor(double val, int maxVal)
{
    if(maxVal <= 0) return UI_CLR_DIM;
    double pct = val / (double)maxVal;
    if(pct >= 0.60) return UI_CLR_BAD;
    if(pct >= 0.35) return UI_CLR_MED;
    return UI_CLR_DIM;
}

//+------------------------------------------------------------------+
//|  PeriodToStr                                                     |
//+------------------------------------------------------------------+

string PeriodToStr()
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
//|  BuildPanel — creates all objects once                           |
//+------------------------------------------------------------------+

void BuildPanel()
{
    string p = g_prefix;

    //--- Compute total panel height
    int totalH = UI_HDR_H;
    totalH += 4 + 14 + UI_ROW * 2;
    totalH += UI_SEC_GAP + UI_SEP_H + UI_SEC_GAP;
    totalH += 14 + 13 + UI_SML * 7;
    totalH += UI_SEC_GAP + UI_SEP_H + UI_SEC_GAP;
    totalH += 14 + UI_ROW * 4 + 2 + UI_SEP_H + 3 + UI_SML * 7;
    totalH += UI_SEC_GAP + UI_SEP_H + UI_SEC_GAP;
    totalH += 14 + UI_ROW * 2;
    totalH += UI_SEC_GAP + UI_SEP_H + UI_SEC_GAP;
    totalH += 14 + UI_ROW;
    totalH += UI_SEC_GAP;
    totalH += (UI_BTN_H + 3) * 3 + 8;

    int cy = UI_Y;

    //--- Main background
    UI_CreateRect(p + "BG", UI_X, UI_Y, UI_W, totalH, UI_CLR_PANEL_BG);

    //--- HEADER
    UI_CreateRect (p + "HDR_BG",    UI_X,           cy,    UI_W, UI_HDR_H, UI_CLR_HDR_BG);
    UI_CreateLabel(p + "HDR_TITLE", UI_COL1,         cy+5, "▪ SmartEdge v1.0", UI_CLR_WHITE, UI_SZ_HDR);
    UI_CreateLabel(p + "HDR_SYM",   UI_X + UI_W - 88, cy+7, "—",               UI_CLR_DIM,   UI_SZ);
    cy += UI_HDR_H;

    //--- PRE-ENTRY SCORES
    cy += 4;
    UI_CreateLabel(p + "TTL_SCORES", UI_COL1, cy, "PRE-ENTRY SCORES", UI_CLR_DIM, UI_SZ_SM);
    cy += 14;

    UI_CreateLabel(p + "LBL_BUY",    UI_COL1,      cy, "BUY",  UI_CLR_BUY,  UI_SZ);
    UI_CreateLabel(p + "VAL_BSCORE", UI_COL2,      cy, "---",  UI_CLR_TEXT, UI_SZ);
    UI_CreateLabel(p + "VAL_BCLASS", UI_COL2 + 50, cy, "---",  UI_CLR_TEXT, UI_SZ);
    cy += UI_ROW;

    UI_CreateLabel(p + "LBL_SELL",   UI_COL1,      cy, "SELL", UI_CLR_SELL, UI_SZ);
    UI_CreateLabel(p + "VAL_SSCORE", UI_COL2,      cy, "---",  UI_CLR_TEXT, UI_SZ);
    UI_CreateLabel(p + "VAL_SCLASS", UI_COL2 + 50, cy, "---",  UI_CLR_TEXT, UI_SZ);
    cy += UI_ROW + UI_SEC_GAP;

    UI_CreateRect(p + "SEP1", UI_X + 6, cy, UI_W - 12, UI_SEP_H, UI_CLR_SEP);
    cy += UI_SEP_H + UI_SEC_GAP;

    //--- BREAKDOWN TABLE
    UI_CreateLabel(p + "TTL_BRK",  UI_COL1, cy, "BREAKDOWN", UI_CLR_DIM,  UI_SZ_SM);
    UI_CreateLabel(p + "BRK_COLB", UI_COL2, cy, "Buy",       UI_CLR_BUY,  UI_SZ_SM);
    UI_CreateLabel(p + "BRK_COLS", UI_COL3, cy, "Sell",      UI_CLR_SELL, UI_SZ_SM);
    cy += 13;

    string brkKeys[7]  = {"TREND","STRUCT","LOC","CANDLE","MOM","RR","PEN"};
    string brkNames[7] = {"Trend","Structure","Location","Candle","Momentum","R:R","Penalty"};
    for(int i = 0; i < 7; i++)
    {
        color lc = (i == 6) ? UI_CLR_PEN : UI_CLR_DIM;
        UI_CreateLabel(p + "BRKLBL_" + brkKeys[i],  UI_COL1, cy, brkNames[i] + ":", lc,          UI_SZ_SM);
        UI_CreateLabel(p + "BRKBUY_" + brkKeys[i],  UI_COL2, cy, "--",              UI_CLR_TEXT,  UI_SZ_SM);
        UI_CreateLabel(p + "BRKSELL_" + brkKeys[i], UI_COL3, cy, "--",              UI_CLR_TEXT,  UI_SZ_SM);
        cy += UI_SML;
    }

    cy += UI_SEC_GAP;
    UI_CreateRect(p + "SEP2", UI_X + 6, cy, UI_W - 12, UI_SEP_H, UI_CLR_SEP);
    cy += UI_SEP_H + UI_SEC_GAP;

    //--- ACTIVE TRADE
    UI_CreateLabel(p + "TTL_TRADE", UI_COL1, cy, "ACTIVE TRADE", UI_CLR_DIM, UI_SZ_SM);
    cy += 14;

    string tradeLabels[4]   = {"Direction:","Bars held:","Exhaustion:","State:"};
    string tradeValNames[4] = {"DIR","BARS","EXH","STATE"};
    string tradeDefaults[4] = {"None","—","—","Inactive"};
    for(int i = 0; i < 4; i++)
    {
        UI_CreateLabel(p + "LBL_" + tradeValNames[i], UI_COL1, cy, tradeLabels[i],   UI_CLR_DIM, UI_SZ);
        UI_CreateLabel(p + "VAL_" + tradeValNames[i], UI_COL2, cy, tradeDefaults[i], UI_CLR_DIM, UI_SZ);
        cy += UI_ROW;
    }

    cy += 2;
    UI_CreateRect(p + "SUBDIV", UI_X + 20, cy, UI_W - 40, UI_SEP_H, UI_CLR_SEP);
    cy += UI_SEP_H + 3;

    string exhKeys[7]  = {"E1","E2","E3","E4","E5","E6","EB"};
    string exhNames[7] = {"[1] Momentum","[2] Wicks","[3] Divergence",
                          "[4] Stall","[5] ATR/Vol","[6] Pattern","[B] Trend supp."};
    for(int i = 0; i < 7; i++)
    {
        color lc = (i == 6) ? UI_CLR_GOOD : UI_CLR_DIM;
        UI_CreateLabel(p + "EXHLBL_" + exhKeys[i], UI_COL1 + 6, cy, exhNames[i] + ":", lc,         UI_SZ_SM);
        UI_CreateLabel(p + "EXHVAL_" + exhKeys[i], UI_COL2,      cy, "--",              UI_CLR_DIM, UI_SZ_SM);
        cy += UI_SML;
    }

    cy += UI_SEC_GAP;
    UI_CreateRect(p + "SEP3", UI_X + 6, cy, UI_W - 12, UI_SEP_H, UI_CLR_SEP);
    cy += UI_SEP_H + UI_SEC_GAP;

    //--- ZONES
    UI_CreateLabel(p + "TTL_ZONES", UI_COL1, cy, "SUGGESTED ZONES", UI_CLR_DIM, UI_SZ_SM);
    cy += 14;

    UI_CreateLabel(p + "LBL_STOP", UI_COL1, cy, "Stop zone:",   UI_CLR_DIM,  UI_SZ);
    UI_CreateLabel(p + "VAL_STOP", UI_COL2, cy, "---",          UI_CLR_TEXT, UI_SZ);
    cy += UI_ROW;

    UI_CreateLabel(p + "LBL_TGT",  UI_COL1, cy, "Target zone:", UI_CLR_DIM,  UI_SZ);
    UI_CreateLabel(p + "VAL_TGT",  UI_COL2, cy, "---",          UI_CLR_TEXT, UI_SZ);
    cy += UI_ROW + UI_SEC_GAP;

    UI_CreateRect(p + "SEP4", UI_X + 6, cy, UI_W - 12, UI_SEP_H, UI_CLR_SEP);
    cy += UI_SEP_H + UI_SEC_GAP;

    //--- NOTES
    UI_CreateLabel(p + "TTL_NOTES", UI_COL1, cy, "NOTES", UI_CLR_DIM, UI_SZ_SM);
    cy += 14;
    UI_CreateLabel(p + "VAL_NOTES", UI_COL1, cy, "—", UI_CLR_DIM, UI_SZ_SM);
    cy += UI_ROW + UI_SEC_GAP;

    //--- BUTTONS
    int bw  = (UI_W - 16) / 2;
    int bx1 = UI_X + 4;
    int bx2 = UI_X + 4 + bw + 4;

    // Row 1: Evaluate
    UI_CreateButton(p + "BTN_EVALBUY",  bx1, cy, bw, UI_BTN_H, "Evaluate Buy",  UI_CLR_BTN_BUY_BG,  UI_CLR_BUY);
    UI_CreateButton(p + "BTN_EVALSELL", bx2, cy, bw, UI_BTN_H, "Evaluate Sell", UI_CLR_BTN_SELL_BG, UI_CLR_SELL);
    cy += UI_BTN_H + 3;

    // Row 2: Mark active
    UI_CreateButton(p + "BTN_MARKBUY",  bx1, cy, bw, UI_BTN_H, "Mark Active BUY",  UI_CLR_BTN_MARK_BG,  UI_CLR_BUY);
    UI_CreateButton(p + "BTN_MARKSELL", bx2, cy, bw, UI_BTN_H, "Mark Active SELL", UI_CLR_BTN_MARKS_BG, UI_CLR_SELL);
    cy += UI_BTN_H + 3;

    // Row 3: Clear (full width)
    UI_CreateButton(p + "BTN_CLEAR", bx1, cy, UI_W - 8, UI_BTN_H, "Clear Active Trade", UI_CLR_BTN_CLR_BG, UI_CLR_DIM);

    ChartRedraw();
}

//+------------------------------------------------------------------+
//|  RefreshPanel — updates values only, never creates/destroys      |
//+------------------------------------------------------------------+

void RefreshPanel()
{
    string p      = g_prefix;
    int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

    //--- Header symbol
    UI_SetTextColor(p + "HDR_SYM", _Symbol + " " + PeriodToStr(), UI_CLR_DIM);

    //--- Pre-entry scores
    UI_SetTextColor(p + "VAL_BSCORE", DoubleToString(g_score.buyTotal,  1), ScoreColor(g_score.buyTotal));
    UI_SetTextColor(p + "VAL_SSCORE", DoubleToString(g_score.sellTotal, 1), ScoreColor(g_score.sellTotal));
    UI_SetTextColor(p + "VAL_BCLASS", "[" + g_score.buyClass  + "]",        ClassColor(g_score.buyClass));
    UI_SetTextColor(p + "VAL_SCLASS", "[" + g_score.sellClass + "]",        ClassColor(g_score.sellClass));

    //--- Breakdown
    double bVals[7] = {
        g_score.buyComp.trend,
        g_score.buyComp.structure,
        g_score.buyComp.location,
        g_score.buyComp.candle,
        g_score.buyComp.momentum,
        g_score.buyComp.rr,
        g_score.buyPenalty
    };
    double sVals[7] = {
        g_score.sellComp.trend,
        g_score.sellComp.structure,
        g_score.sellComp.location,
        g_score.sellComp.candle,
        g_score.sellComp.momentum,
        g_score.sellComp.rr,
        g_score.sellPenalty
    };
    int maxVals[7] = {
        InpWtTrend,
        InpWtStructure,
        InpWtLocation,
        InpWtCandle,
        InpWtMomentum,
        InpWtRR,
        0
    };
    string brkKeys[7] = {"TREND","STRUCT","LOC","CANDLE","MOM","RR","PEN"};

    for(int i = 0; i < 7; i++)
    {
        color  bc, sc;
        string bStr, sStr;

        if(i == 6)
        {
            bc   = (bVals[6] < -5.0) ? UI_CLR_BAD : UI_CLR_DIM;
            sc   = (sVals[6] < -5.0) ? UI_CLR_BAD : UI_CLR_DIM;
            bStr = DoubleToString(bVals[6], 1);
            sStr = DoubleToString(sVals[6], 1);
        }
        else
        {
            bc   = ComponentColor(bVals[i], maxVals[i]);
            sc   = ComponentColor(sVals[i], maxVals[i]);
            bStr = DoubleToString(bVals[i], 1);
            sStr = DoubleToString(sVals[i], 1);
        }

        UI_SetTextColor(p + "BRKBUY_"  + brkKeys[i], bStr, bc);
        UI_SetTextColor(p + "BRKSELL_" + brkKeys[i], sStr, sc);
    }

    //--- Active trade section
    if(g_trade.tradeState != TRADE_IDLE)
    {
        color  dClr   = (g_trade.tradeState == TRADE_ACTIVE_BUY) ? UI_CLR_BUY  : UI_CLR_SELL;
        string dirStr = (g_trade.tradeState == TRADE_ACTIVE_BUY) ? "BUY"        : "SELL";

        UI_SetTextColor(p + "VAL_DIR",   dirStr,                                    dClr);
        UI_SetTextColor(p + "VAL_BARS",  IntegerToString(g_trade.barsHeld),         UI_CLR_TEXT);
        UI_SetTextColor(p + "VAL_EXH",   DoubleToString(g_trade.exhaustion, 1),     ExhaustionColor(g_trade.exhaustion));
        UI_SetTextColor(p + "VAL_STATE", g_trade.healthText,                        HealthStateColor(g_trade.healthState));

        double exhVals[7] = {
            g_trade.exh_momentum,
            g_trade.exh_wick,
            g_trade.exh_divergence,
            g_trade.exh_stall,
            g_trade.exh_atr,
            g_trade.exh_pattern,
            g_trade.exh_trendBonus
        };
        int exhMax[7] = {25, 20, 20, 15, 10, 10, 25};
        string exhKeys[7] = {"E1","E2","E3","E4","E5","E6","EB"};

        for(int i = 0; i < 6; i++)
        {
            color vc = ExhaustionComponentColor(exhVals[i], exhMax[i]);
            UI_SetTextColor(p + "EXHVAL_" + exhKeys[i], DoubleToString(exhVals[i], 1), vc);
        }

        // Trend suppression bonus shown as negative value
        string bonusStr = "-" + DoubleToString(exhVals[6], 1);
        color  bonusClr = (exhVals[6] > 5.0) ? UI_CLR_GOOD : UI_CLR_DIM;
        UI_SetTextColor(p + "EXHVAL_EB", bonusStr, bonusClr);
    }
    else
    {
        UI_SetTextColor(p + "VAL_DIR",   "None",     UI_CLR_DIM);
        UI_SetTextColor(p + "VAL_BARS",  "—",        UI_CLR_DIM);
        UI_SetTextColor(p + "VAL_EXH",   "—",        UI_CLR_DIM);
        UI_SetTextColor(p + "VAL_STATE", "Inactive", UI_CLR_DIM);

        string exhKeys2[7] = {"E1","E2","E3","E4","E5","E6","EB"};
        for(int i = 0; i < 7; i++)
            UI_SetTextColor(p + "EXHVAL_" + exhKeys2[i], "—", UI_CLR_DIM);
    }

    //--- Zones
    if(g_atr > 0.0)
    {
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        UI_SetTextColor(p + "VAL_STOP",
            DoubleToString(bid - g_score.suggestStop, digits) + "  (-" +
            DoubleToString(g_score.suggestStop / g_atr, 1) + "R)",
            UI_CLR_BAD);
        UI_SetTextColor(p + "VAL_TGT",
            DoubleToString(bid + g_score.suggestTarget, digits) + "  (+" +
            DoubleToString(g_score.suggestTarget / g_atr, 1) + "R)",
            UI_CLR_GOOD);
    }
    else
    {
        UI_SetTextColor(p + "VAL_STOP", "---", UI_CLR_DIM);
        UI_SetTextColor(p + "VAL_TGT",  "---", UI_CLR_DIM);
    }

    //--- Notes
    string notes = (StringLen(g_score.reasons) > 0) ? g_score.reasons : "No active warnings";
    if(StringLen(notes) > 44)
        notes = StringSubstr(notes, 0, 44) + "…";
    UI_SetTextColor(p + "VAL_NOTES", notes, UI_CLR_DIM);

    ChartRedraw();
}

//+------------------------------------------------------------------+
//|  DeleteAllUIObjects                                              |
//+------------------------------------------------------------------+

void DeleteAllUIObjects()
{
    ObjectsDeleteAll(0, g_prefix);
}

//+------------------------------------------------------------------+
//|  HandleButtonClick                                               |
//+------------------------------------------------------------------+

void HandleButtonClick(const string sparam)
{
    if(sparam == g_prefix + "BTN_EVALBUY" ||
       sparam == g_prefix + "BTN_EVALSELL")
    {
        RunFullScoring();
        RefreshPanel();
    }
    else if(sparam == g_prefix + "BTN_MARKBUY")
    {
        ActivateTrade(TRADE_ACTIVE_BUY);
        RefreshPanel();
    }
    else if(sparam == g_prefix + "BTN_MARKSELL")
    {
        ActivateTrade(TRADE_ACTIVE_SELL);
        RefreshPanel();
    }
    else if(sparam == g_prefix + "BTN_CLEAR")
    {
        ClearTrade();
        RefreshPanel();
    }

    // Reset button visual state so it does not stay pressed
    if(StringFind(sparam, g_prefix) == 0 &&
       StringFind(sparam, "BTN_") != -1)
    {
        ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
    }

    ChartRedraw();
}

#endif // __SMARTEDGE_UI_MQH__
