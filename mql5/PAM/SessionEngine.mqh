//+------------------------------------------------------------------+
//| PAM/SessionEngine.mqh  —  Trading Session Shading               |
//|                                                                  |
//| SMC Context:                                                     |
//|   Sessions define WHEN institutions are active. Understanding   |
//|   which session created a move tells you WHO is behind it:      |
//|                                                                  |
//|   ASIAN  (22:00–07:00 UTC) — Low volatility, range creation.   |
//|             Often forms the liquidity pool that London sweeps.   |
//|                                                                  |
//|   LONDON (07:00–16:00 UTC) — Highest volume. Trend initiation. |
//|             BOS/MSS events here carry the most institutional     |
//|             weight. London frequently sweeps Asian highs/lows.   |
//|                                                                  |
//|   NEW YORK (12:00–21:00 UTC) — Second highest volume.          |
//|             NY open often confirms or reverses London direction.  |
//|             NFP, FOMC, and major USD events happen here.         |
//|                                                                  |
//|   OVERLAP (12:00–16:00 UTC) — London + NY simultaneously.      |
//|             Highest liquidity window of the day. Most reliable   |
//|             for displacement and continuation trades.             |
//+------------------------------------------------------------------+
#ifndef PAM_SESSION_MQH
#define PAM_SESSION_MQH
#include "Context.mqh"

//--- Session identifiers (internal to this engine)
enum ESession
{
   SESS_NONE    = 0,
   SESS_ASIAN,
   SESS_LONDON,
   SESS_NY,
   SESS_OVERLAP     // London + NY simultaneously (12:00–16:00)
};

//+------------------------------------------------------------------+
// GetSession
//   Returns the dominant session for a given broker-local hour.
//   Overlap is prioritised over both London and NY.
//   Hours are compared modulo 24 to handle overnight sessions.
//+------------------------------------------------------------------+
ESession GetSession(int hour,
                    int asianOpen,  int asianClose,
                    int londonOpen, int londonClose,
                    int nyOpen,     int nyClose)
{
   // Build simple booleans. Overnight sessions (asianOpen > asianClose)
   // need the wrap-around check.
   bool inAsian, inLondon, inNY;

   if(asianOpen < asianClose)
      inAsian = (hour >= asianOpen && hour < asianClose);
   else
      inAsian = (hour >= asianOpen || hour < asianClose);  // wraps midnight

   inLondon = (hour >= londonOpen && hour < londonClose);
   inNY     = (hour >= nyOpen     && hour < nyClose);

   if(inLondon && inNY) return SESS_OVERLAP;
   if(inLondon)         return SESS_LONDON;
   if(inNY)             return SESS_NY;
   if(inAsian)          return SESS_ASIAN;
   return SESS_NONE;
}

//+------------------------------------------------------------------+
// SessionEngine_Draw
//   Draws background rectangles showing session price ranges for
//   the last ctx.sessDays calendar days. Each contiguous block of
//   same-session bars is one rectangle spanning its actual H/L.
//
//   Parameters:
//     ctx       — shared context (reads session config, lookback)
//     time[]    — series time array (index 0 = newest bar)
//     high[]    — series high array
//     low[]     — series low array
//     total     — total bars on chart
//     pfx       — object name prefix ("PAM_")
//+------------------------------------------------------------------+
void SessionEngine_Draw(const SPAMContext &ctx,
                        const datetime    &time[],
                        const double      &high[],
                        const double      &low[],
                        int                total,
                        const string      &pfx)
{
   if(!ctx.showSessions) return;

   // Maximum bars to scan: limit to lookback or available bars
   int limit = MathMin(ctx.lookback, total - 1);

   // --- First pass: delete existing session box objects ---
   // Prefix "SBOX" avoids collision with the dashboard label "SESS"
   for(int obj = ObjectsTotal(0, 0, -1) - 1; obj >= 0; obj--)
   {
      string nm = ObjectName(0, obj, 0, -1);
      if(StringFind(nm, pfx + "SBOX") == 0)
         ObjectDelete(0, nm);
   }

   // --- Second pass: scan bars oldest→newest, build segments ---
   // We work from bar index `limit` (oldest) down to 0 (newest).
   // Series arrays: index 0=newest, index limit=oldest.

   ESession curSess   = SESS_NONE;
   double   segHigh   = -DBL_MAX;
   double   segLow    =  DBL_MAX;
   datetime segStart  = 0;   // time of the oldest bar in the segment
   datetime segEnd    = 0;   // time of the newest bar in the segment
   int      boxCount  = 0;
   int      maxBoxes  = ctx.sessDays * 5;   // up to 5 segments per day

   // Collect segments by scanning oldest→newest
   // We iterate from high index (oldest) to index 0 (newest)
   for(int i = limit; i >= 0; i--)
   {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      ESession thisSess = GetSession(dt.hour,
                                     ctx.asianOpenH,  ctx.asianCloseH,
                                     ctx.londonOpenH, ctx.londonCloseH,
                                     ctx.nyOpenH,     ctx.nyCloseH);

      // Filter: skip sessions the user disabled
      if(thisSess == SESS_ASIAN   && !ctx.showAsian)   thisSess = SESS_NONE;
      if(thisSess == SESS_LONDON  && !ctx.showLondon)  thisSess = SESS_NONE;
      if(thisSess == SESS_NY      && !ctx.showNY)      thisSess = SESS_NONE;
      if(thisSess == SESS_OVERLAP && !ctx.showOverlap) thisSess = SESS_NONE;

      if(thisSess == curSess && thisSess != SESS_NONE)
      {
         // Extend current segment
         segHigh = MathMax(segHigh, high[i]);
         segLow  = MathMin(segLow,  low[i]);
         segEnd  = time[i];   // newest bar = most-right on chart
      }
      else
      {
         // Flush previous segment if it was a real session
         if(curSess != SESS_NONE && boxCount < maxBoxes)
         {
            // Build name from segment start timestamp
            string nm = pfx + "SBOX" + IntegerToString((int)segStart);

            // Determine color
            color fillCol, borderCol;
            string sessLabel;
            switch(curSess)
            {
               case SESS_ASIAN:
                  fillCol   = C'15,15,35';
                  borderCol = C'40,40,100';
                  sessLabel = "AS";
                  break;
               case SESS_LONDON:
                  fillCol   = C'10,30,15';
                  borderCol = C'30,100,45';
                  sessLabel = "LN";
                  break;
               case SESS_NY:
                  fillCol   = C'35,12,12';
                  borderCol = C'110,35,35';
                  sessLabel = "NY";
                  break;
               case SESS_OVERLAP:
                  fillCol   = C'35,25,8';
                  borderCol = C'130,95,25';
                  sessLabel = "OV";
                  break;
               default:
                  fillCol   = C'10,10,10';
                  borderCol = clrGray;
                  sessLabel = "";
                  break;
            }

            // Draw the rectangle from segStart to segEnd with segHigh/segLow
            ObjectCreate(0, nm, OBJ_RECTANGLE, 0, segStart, segHigh, segEnd, segLow);
            ObjectSetInteger(0, nm, OBJPROP_COLOR,      borderCol);
            ObjectSetInteger(0, nm, OBJPROP_STYLE,      ctx.outlineMode ? STYLE_DOT : STYLE_SOLID);
            ObjectSetInteger(0, nm, OBJPROP_WIDTH,      1);
            ObjectSetInteger(0, nm, OBJPROP_FILL,       !ctx.outlineMode);
            ObjectSetInteger(0, nm, OBJPROP_BGCOLOR,    fillCol);
            ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
            ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);

            // Label at top-left of rectangle
            string lnm = pfx + "SBOXL" + IntegerToString((int)segStart);
            ObjectCreate(0, lnm, OBJ_TEXT, 0, segStart, segHigh);
            ObjectSetString(0,  lnm, OBJPROP_TEXT,      sessLabel);
            ObjectSetInteger(0, lnm, OBJPROP_COLOR,     borderCol);
            ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE,  6);
            ObjectSetString(0,  lnm, OBJPROP_FONT,      "Consolas");
            ObjectSetInteger(0, lnm, OBJPROP_ANCHOR,    ANCHOR_LOWER);
            ObjectSetInteger(0, lnm, OBJPROP_BACK,      true);
            ObjectSetInteger(0, lnm, OBJPROP_SELECTABLE,false);

            boxCount++;
         }

         // Start new segment
         curSess  = thisSess;
         segHigh  = (thisSess != SESS_NONE) ? high[i] : -DBL_MAX;
         segLow   = (thisSess != SESS_NONE) ? low[i]  :  DBL_MAX;
         segStart = time[i];
         segEnd   = time[i];
      }
   }

   // Flush the final open segment (most recent bars)
   if(curSess != SESS_NONE && boxCount < maxBoxes)
   {
      string nm = pfx + "SBOX" + IntegerToString((int)segStart);
      color fillCol, borderCol;
      string sessLabel;
      switch(curSess)
      {
         case SESS_ASIAN:
            fillCol   = C'15,15,35';
            borderCol = C'40,40,100';
            sessLabel = "AS";
            break;
         case SESS_LONDON:
            fillCol   = C'10,30,15';
            borderCol = C'30,100,45';
            sessLabel = "LN";
            break;
         case SESS_NY:
            fillCol   = C'35,12,12';
            borderCol = C'110,35,35';
            sessLabel = "NY";
            break;
         case SESS_OVERLAP:
            fillCol   = C'35,25,8';
            borderCol = C'130,95,25';
            sessLabel = "OV";
            break;
         default:
            fillCol   = C'10,10,10';
            borderCol = clrGray;
            sessLabel = "";
            break;
      }

      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, segStart, segHigh, segEnd, segLow);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      borderCol);
      ObjectSetInteger(0, nm, OBJPROP_STYLE,      STYLE_SOLID);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,      1);
      ObjectSetInteger(0, nm, OBJPROP_FILL,       true);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR,    fillCol);
      ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);

      string lnm = pfx + "SBOXL" + IntegerToString((int)segStart);
      ObjectCreate(0, lnm, OBJ_TEXT, 0, segStart, segHigh);
      ObjectSetString(0,  lnm, OBJPROP_TEXT,      sessLabel);
      ObjectSetInteger(0, lnm, OBJPROP_COLOR,     borderCol);
      ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE,  6);
      ObjectSetString(0,  lnm, OBJPROP_FONT,      "Consolas");
      ObjectSetInteger(0, lnm, OBJPROP_ANCHOR,    ANCHOR_LOWER);
      ObjectSetInteger(0, lnm, OBJPROP_BACK,      true);
      ObjectSetInteger(0, lnm, OBJPROP_SELECTABLE,false);
   }
}

//+------------------------------------------------------------------+
// SessionEngine_CurrentString
//   Returns a one-line dashboard string for the current session.
//+------------------------------------------------------------------+
string SessionEngine_CurrentString(const SPAMContext &ctx)
{
   if(!ctx.showSessions) return "  Sessions   hidden";

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   ESession s = GetSession(dt.hour,
                           ctx.asianOpenH,  ctx.asianCloseH,
                           ctx.londonOpenH, ctx.londonCloseH,
                           ctx.nyOpenH,     ctx.nyCloseH);
   switch(s)
   {
      case SESS_ASIAN:   return "  Session    ASIAN  (range building)";
      case SESS_LONDON:  return "  Session    LONDON (high volume)";
      case SESS_NY:      return "  Session    NEW YORK";
      case SESS_OVERLAP: return "  Session    OVERLAP — peak liquidity";
      default:           return "  Session    Off-session";
   }
}

#endif // PAM_SESSION_MQH
