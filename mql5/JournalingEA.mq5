//+------------------------------------------------------------------+
//|                                              JournalingEA.mq5     |
//|  MT5 -> TradeMind ingestion (POST /api/trades/ingest)             |
//|  Uses HistoryDealGet* for time/profit/commission/swap (correct)   |
//|  Tracks near-perfect MAE/MFE via Bid/Ask while position is open   |
//+------------------------------------------------------------------+
#property strict

// -------------------- Inputs --------------------
input string API_BASE_URL        = "https://your-domain.com"; // no trailing slash
input string API_PATH            = "/api/trades/ingest";
input string INGESTION_KEY       = "YOUR_INGESTION_KEY";
input string BROKER_NAME         = "Deriv";
input string ACCOUNT_ID_OVERRIDE = ""; // if empty uses MT5 login
input string DEFAULT_SETUP       = ""; // optional setup name (sent if not empty)

input int    RETRY_TIMER_SECONDS = 3;
input int    MAX_QUEUE_LINES     = 5000;



input bool   ENABLE_LOGS   = true;
input bool   SHOW_STATUS   = true;

input int  SYNC_DAYS_BACK = 30;      // how far back to backfill
input int  SYNC_MAX_DEALS = 2000;    // safety cap


bool g_sync_in_progress = false;




string BTN_NAME = "TM_TEST_INGEST_BTN";
string g_last_status = "Idle";
int    g_last_code = 0;

void Log(string msg)
{
  if(ENABLE_LOGS) Print("[JOURNAL_EA] ", msg);
}

void UpdateStatus()
{
  if(!SHOW_STATUS) return;
  Comment("TradeMind Journal EA\n",
          "Status: ", g_last_status, "\n",
          "HTTP: ", IntegerToString(g_last_code), "\n",
          "URL: ", Url(), "\n",
          "QueueFile: ", QueueFile());
}


// -------------------- Track open positions --------------------
struct TrackState
{
  ulong    position_ticket;      // ticket (PositionSelectByTicket)
  ulong    position_identifier;  // identifier (POSITION_IDENTIFIER / DEAL_POSITION_ID)

  string   symbol;
  int      side;
  double   volume;

  double   entry_price;
  datetime entry_time;

  double   sl_price;
  double   tp_price;

  double   mae_price;
  datetime mae_time;
  double   mfe_price;
  datetime mfe_time;

  double   mae_points;
  double   mfe_points;

  double   min_floating_profit;   // most negative floating PnL seen during trade
  double   max_floating_profit;   // most positive floating PnL seen during trade
  double   mae_cash_live;         // drawdown in cash (derived from min_floating_profit)
  double   mfe_cash_live;         // run-up in cash (derived from max_floating_profit)
  double   entry_balance;
  double   entry_equity;
   };


TrackState tracks[];
int tracks_count = 0;

// -------------------- Helpers --------------------
string NormalizeSymbol(string sym)
{
  string s = sym;

  // Normalize common Deriv synthetics
  StringReplace(s, "Volatility ", "V");
  StringReplace(s, " (1s)", "_1S");
  StringReplace(s, " Index", "");
  StringReplace(s, " ", "");
  StringReplace(s, "(", "");
  StringReplace(s, ")", "");

  // Hard cap for server constraint
  if(StringLen(s) > 20)
    s = StringSubstr(s, 0, 20);

  return s;
}



string GetAccountId()
{
  if(StringLen(ACCOUNT_ID_OVERRIDE) > 0) return ACCOUNT_ID_OVERRIDE;
  return (string)AccountInfoInteger(ACCOUNT_LOGIN);
}

string Url()
{
  string base = API_BASE_URL;
  if(StringLen(base) == 0) return "";
  if(StringSubstr(base, StringLen(base)-1, 1) == "/")
    base = StringSubstr(base, 0, StringLen(base)-1);
  return base + API_PATH;
}

datetime NowUTC() { return TimeGMT(); }

string ToIso8601UTC(datetime t)
{
  if(t <= 0) return "";
  MqlDateTime dt;
  TimeToStruct(t, dt);
  return StringFormat("%04d-%02d-%02dT%02d:%02d:%02d.000Z",
                      dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

double PointsBetween(string sym, double a, double b)
{
  double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
  if(pt <= 0) return 0.0;
  return MathAbs(a - b) / pt;
}

string JsonEscape(string s)
{
  StringReplace(s, "\\", "\\\\");
  StringReplace(s, "\"", "\\\"");
  StringReplace(s, "\r", "\\r");
  StringReplace(s, "\n", "\\n");
  StringReplace(s, "\t", "\\t");
  return s;
}

int FindTrackByIdentifier(ulong position_identifier)
{
  for(int i=0;i<tracks_count;i++)
    if(tracks[i].position_identifier == position_identifier)
      return i;
  return -1;
}


void RemoveTrack(int idx)
{
  if(idx < 0 || idx >= tracks_count) return;
  for(int i=idx;i<tracks_count-1;i++) tracks[i] = tracks[i+1];
  tracks_count--;
  ArrayResize(tracks, tracks_count);
}

// Compute cash from points using symbol tick value/size.
// Returns 0 if symbol doesn't provide these reliably.
double CashFromPoints(string sym, double points, double volume)
{
  double tick_value=0, tick_size=0, pt=0;
  if(!SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE, tick_value)) return 0.0;
  if(!SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE, tick_size)) return 0.0;
  if(!SymbolInfoDouble(sym, SYMBOL_POINT, pt)) return 0.0;
  if(tick_size <= 0) return 0.0;

  double value_per_price_unit_per_lot = tick_value / tick_size; // per 1.0 price move per lot
  double value_per_point_per_lot = value_per_price_unit_per_lot * pt;

  return points * value_per_point_per_lot * volume;
}

// -------------------- HTTP POST --------------------
bool PostJson(const string url,
              const string json,
              string &resp_headers,
              string &resp_body,
              int &code)
{
  // Convert string to UTF-8 bytes WITHOUT sending trailing '\0'
  char data[];
  int len = StringToCharArray(json, data, 0, StringLen(json), CP_UTF8);
  // StringToCharArray returns bytes copied including possible terminator depending on args,
  // so we explicitly size the array to "len - 1" if terminator was added.
  // Easiest safe approach: trim one byte if last is 0.
  int sz = ArraySize(data);
  if(sz > 0 && data[sz-1] == 0)
    ArrayResize(data, sz-1);

  char result[];
  string headers =
    "Content-Type: application/json\r\n" +
    "Authorization: Bearer " + INGESTION_KEY + "\r\n";

  ResetLastError();
  int timeout_ms = 7000;

  code = WebRequest("POST", url, headers, timeout_ms, data, result, resp_headers);
  if(code == -1)
  {
    resp_headers = "WebRequest failed. err=" + IntegerToString(GetLastError());
    resp_body = "";
    return false;
  }

  resp_body = CharArrayToString(result, 0, -1, CP_UTF8);
  return (code >= 200 && code < 300);
}


void SyncHistory()
{
  datetime to_time = TimeCurrent();
  datetime from_time = to_time - (datetime)(SYNC_DAYS_BACK * 86400);

  g_last_status = "Syncing history...";
  UpdateStatus();

  if(!HistorySelect(from_time, to_time))
  {
    Log("SyncHistory: HistorySelect failed. err=" + IntegerToString(GetLastError()));
    g_last_status = "Sync failed (HistorySelect)";
    UpdateStatus();
    return;
  }

  int total = HistoryDealsTotal();
  Log("SyncHistory: deals_total=" + IntegerToString(total) +
      " from=" + TimeToString(from_time) + " to=" + TimeToString(to_time));

  //--- FIX: Pre-collect all closing deal tickets into an array FIRST.
  //--- BuildPayloadFromDeal -> FillEntryFromHistory calls HistorySelect()
  //--- with a different range, which corrupts deal indices mid-loop.
  //--- By collecting tickets upfront, we avoid index corruption.
  ulong close_deals[];
  int close_count = 0;

  for(int i = total - 1; i >= 0; i--)
  {
    ulong deal_id = HistoryDealGetTicket(i);
    if(deal_id == 0) continue;
    if(!HistoryDealSelect(deal_id)) continue;

    long entry = HistoryDealGetInteger(deal_id, DEAL_ENTRY);
    if(!(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)) continue;

    string sym = (string)HistoryDealGetString(deal_id, DEAL_SYMBOL);
    if(StringLen(sym) == 0) continue;

    ArrayResize(close_deals, close_count + 1);
    close_deals[close_count++] = deal_id;
  }

  Log("SyncHistory: closing_deals=" + IntegerToString(close_count));

  int sent=0, queued=0, skipped=0, dupes=0;

  for(int i = 0; i < close_count; i++)
  {
    if(sent + queued >= SYNC_MAX_DEALS) break;

    ulong deal_id = close_deals[i];

    //--- Re-select history before each deal (FillEntryFromHistory may change it)
    HistorySelect(from_time, to_time);

    if(!HistoryDealSelect(deal_id)) { skipped++; continue; }

    ulong position_identifier = (ulong)HistoryDealGetInteger(deal_id, DEAL_POSITION_ID);

    string payload = BuildPayloadFromDeal(deal_id, position_identifier);
    Log("WHOLE_BODY=" + payload);
    if(StringLen(payload) == 0) { skipped++; continue; }

    string resp_headers="", resp_body="";
    int code=0;

    bool ok = PostJson(Url(), payload, resp_headers, resp_body, code);

    if(ok)
    {
      sent++;
    }
    else if(code == 409)
    {
      //--- Trade already exists in database — not an error
      dupes++;
    }
    else
    {
      QueueAppend(payload);
      queued++;
      Log("SyncHistory: queued deal_id=" + (string)deal_id +
          " http=" + IntegerToString(code) + " body=" + resp_body);
    }

    if(((sent+queued+dupes) % 50) == 0)
      Log("Sync progress: sent=" + IntegerToString(sent) +
          " dupes=" + IntegerToString(dupes) +
          " queued=" + IntegerToString(queued) +
          " skipped=" + IntegerToString(skipped));
  }

  g_last_status = "Sync done: sent=" + IntegerToString(sent) +
                  " dupes=" + IntegerToString(dupes) +
                  " queued=" + IntegerToString(queued) +
                  " skipped=" + IntegerToString(skipped);
  Log(g_last_status);
  UpdateStatus();
}



void CreateTestButton()
{
  // delete if exists
  ObjectDelete(0, BTN_NAME);

  // create button
  if(!ObjectCreate(0, BTN_NAME, OBJ_BUTTON, 0, 0, 0))
  {
    Log("Failed to create button. err=" + IntegerToString(GetLastError()));
    return;
  }

  ObjectSetInteger(0, BTN_NAME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
  ObjectSetInteger(0, BTN_NAME, OBJPROP_XDISTANCE, 10);
  ObjectSetInteger(0, BTN_NAME, OBJPROP_YDISTANCE, 20);
  ObjectSetInteger(0, BTN_NAME, OBJPROP_XSIZE, 140);
  ObjectSetInteger(0, BTN_NAME, OBJPROP_YSIZE, 28);

  ObjectSetString(0, BTN_NAME, OBJPROP_TEXT, "SYNC DATA");
  ObjectSetInteger(0, BTN_NAME, OBJPROP_FONTSIZE, 10);

  Log("Test button created.");
}

string BuildTestPayload()
{
  // Keep schema-valid. Use unique deal_id so your dedupe doesn't reject it.
  // Using time in seconds makes it unique enough.
  string deal_id = IntegerToString((int)TimeLocal());

  double balance = AccountInfoDouble(ACCOUNT_BALANCE);
  double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

  string nowIso = ToIso8601UTC(NowUTC());

  // Symbol: use current chart symbol for convenience
  string sym = _Symbol;
  int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

  string sym_norm = NormalizeSymbol(sym);

  // Send zeros for trade fields; backend should accept or at least validate schema.
  // If your backend requires positive volume/price, set small dummy numbers.
  string json =
    "{"
      "\"deal_id\":\"" + deal_id + "\","
      "\"account_id\":\"" + JsonEscape(GetAccountId()) + "\","
      "\"broker\":\"" + JsonEscape(BROKER_NAME) + "\","
      "\"symbol\":\"" + JsonEscape(sym_norm) + "\","
      "\"side\":\"BUY\","
      "\"volume\":0.01,"
      "\"entry_price\":" + DoubleToString(SymbolInfoDouble(sym, SYMBOL_BID), digits) + ","
      "\"close_price\":" + DoubleToString(SymbolInfoDouble(sym, SYMBOL_BID), digits) + ","
      "\"sl_price\":0,"
      "\"tp_price\":0,"
      "\"open_time\":\"" + nowIso + "\","
      "\"close_time\":\"" + nowIso + "\","
      "\"pnl\":0,"
      "\"commission\":0,"
      "\"swap\":0,"
      "\"net_pnl\":0,"
      "\"mae\":0,"
      "\"mae_cash\":0,"
      "\"mfe\":0,"
      "\"risk\":0,"
      "\"risk_cash\":0,"
      "\"balance\":" + DoubleToString(balance, 2) + ","
      "\"equity\":" + DoubleToString(equity, 2) + ","
      "\"setup\":\"TEST\","
      "\"notes\":\"EA test button\""
    "}";

  return json;
}

void SendTestIngest()
{
  string payload = BuildTestPayload();

  string resp_headers = "";
  string resp_body    = "";
  int code = 0;

  g_last_status = "Sending test...";
  g_last_code = 0;
  UpdateStatus();

  Log("PAYLOAD_LEN=" + IntegerToString(StringLen(payload)));
  Log("PAYLOAD_TAIL=" + StringSubstr(payload, MathMax(0, StringLen(payload)-120)));


  bool ok = PostJson(Url(), payload, resp_headers, resp_body, code);

  g_last_code = code;

  if(ok)
  {
    g_last_status = "TEST OK";
    Log("TEST INGEST OK. http=" + IntegerToString(code));
    Log("RESP_BODY=" + resp_body);
  }
  else
  {
    g_last_status = "TEST FAILED";
    Log("TEST INGEST FAILED. http=" + IntegerToString(code));
    Log("RESP_BODY=" + resp_body);

    // Optional: also log headers if you want
    // Log("RESP_HEADERS=" + resp_headers);
  }

  UpdateStatus();
}




// -------------------- Queue (file) --------------------
string QueueFile() { return "trademind_queue_" + GetAccountId() + ".txt"; }

void QueueAppend(const string json_line)
{
  int h = FileOpen(QueueFile(), FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI);
  if(h == INVALID_HANDLE) return;

  int lines=0;
  FileSeek(h, 0, SEEK_SET);
  while(!FileIsEnding(h))
  {
    string tmp = FileReadString(h);
    if(StringLen(tmp) > 0) lines++;
  }
  if(lines >= MAX_QUEUE_LINES) { FileClose(h); return; }

  FileSeek(h, 0, SEEK_END);
  FileWrite(h, json_line);
  FileClose(h);
}

bool QueuePopFirst(string &line)
{
  int h = FileOpen(QueueFile(), FILE_READ|FILE_TXT|FILE_ANSI);
  if(h == INVALID_HANDLE) return false;

  string arr[];
  int n=0;
  while(!FileIsEnding(h))
  {
    string ln = FileReadString(h);
    if(StringLen(ln)==0) continue;
    ArrayResize(arr, n+1);
    arr[n++] = ln;
  }
  FileClose(h);
  if(n==0) return false;

  line = arr[0];

  h = FileOpen(QueueFile(), FILE_WRITE|FILE_TXT|FILE_ANSI);
  if(h == INVALID_HANDLE) return true;
  for(int i=1;i<n;i++) FileWrite(h, arr[i]);
  FileClose(h);
  return true;
}

void FlushQueue()
{
  string url = Url();
  if(StringLen(url)==0) return;

  for(int i=0;i<10;i++)
  {
    string ln;
    if(!QueuePopFirst(ln)) return;

    string resp_headers = "";
    string resp_body    = "";
    int code = 0;

    bool ok = PostJson(url, ln, resp_headers, resp_body, code);

    Log("FlushQueue http=" + IntegerToString(code));
    if(StringLen(resp_body) > 0)
      Log("FlushQueue RESP_BODY=" + resp_body);

    if(!ok)
      {
        if(code == 400 || code == 409)
         {
           Log("Dropping queued payload (HTTP " + IntegerToString(code) + ").");
           Log("RESP_BODY=" + resp_body);
           // do NOT requeue — 400 = invalid, 409 = already exists
           continue;
         }


        QueueAppend(ln);
        return;
      }
  }
}


// -------------------- Tracking open positions --------------------
void EnsureTrackForPosition(ulong pos_ticket)
{
  if(!PositionSelectByTicket(pos_ticket)) return;

  ulong pos_ident = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
  if(FindTrackByIdentifier(pos_ident) >= 0) return;

  TrackState t;
  t.position_ticket     = pos_ticket;
  t.position_identifier = pos_ident;

  t.symbol      = PositionGetString(POSITION_SYMBOL);
  t.side        = (int)PositionGetInteger(POSITION_TYPE);
  t.volume      = PositionGetDouble(POSITION_VOLUME);

  t.entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
  t.entry_time  = (datetime)PositionGetInteger(POSITION_TIME);

  t.entry_balance = AccountInfoDouble(ACCOUNT_BALANCE);
  t.entry_equity  = AccountInfoDouble(ACCOUNT_EQUITY);

  t.min_floating_profit = 0.0;
  t.max_floating_profit = 0.0;
  t.mae_cash_live = 0.0;
  t.mfe_cash_live = 0.0;

  t.sl_price    = PositionGetDouble(POSITION_SL);
  t.tp_price    = PositionGetDouble(POSITION_TP);

  t.mae_price   = t.entry_price;
  t.mfe_price   = t.entry_price;
  t.mae_time    = t.entry_time;
  t.mfe_time    = t.entry_time;
  t.mae_points  = 0.0;
  t.mfe_points  = 0.0;

  ArrayResize(tracks, tracks_count+1);
  tracks[tracks_count++] = t;
}


void UpdateTracksOnTick()
{
  for(int i=0;i<tracks_count;i++)
  {
    string sym = tracks[i].symbol;
    SymbolSelect(sym, true);

    double bid=0, ask=0;
    if(!SymbolInfoDouble(sym, SYMBOL_BID, bid)) continue;
    if(!SymbolInfoDouble(sym, SYMBOL_ASK, ask)) continue;

    double px = (tracks[i].side == POSITION_TYPE_BUY) ? bid : ask;

    if(tracks[i].side == POSITION_TYPE_BUY)
    {
      if(px < tracks[i].mae_price)
      {
        tracks[i].mae_price  = px;
        tracks[i].mae_time   = NowUTC();
        tracks[i].mae_points = PointsBetween(sym, tracks[i].entry_price, px);
      }
      if(px > tracks[i].mfe_price)
      {
        tracks[i].mfe_price  = px;
        tracks[i].mfe_time   = NowUTC();
        tracks[i].mfe_points = PointsBetween(sym, tracks[i].entry_price, px);
      }
    }
    else
    {
      if(px > tracks[i].mae_price)
      {
        tracks[i].mae_price  = px;
        tracks[i].mae_time   = NowUTC();
        tracks[i].mae_points = PointsBetween(sym, tracks[i].entry_price, px);
      }
      if(px < tracks[i].mfe_price)
      {
        tracks[i].mfe_price  = px;
        tracks[i].mfe_time   = NowUTC();
        tracks[i].mfe_points = PointsBetween(sym, tracks[i].entry_price, px);
      }
    }

    // keep SL/TP and volume current (optional)
    if(PositionSelectByTicket(tracks[i].position_ticket))
      {
        double fp = PositionGetDouble(POSITION_PROFIT); // floating PnL in deposit currency

        if(fp < tracks[i].min_floating_profit)
          tracks[i].min_floating_profit = fp;

        if(fp > tracks[i].max_floating_profit)
          tracks[i].max_floating_profit = fp;

        tracks[i].mae_cash_live = MathMax(0.0, -tracks[i].min_floating_profit);
        tracks[i].mfe_cash_live = MathMax(0.0,  tracks[i].max_floating_profit);

        // keep SL/TP and volume current (you already do)
        tracks[i].sl_price = PositionGetDouble(POSITION_SL);
        tracks[i].tp_price = PositionGetDouble(POSITION_TP);
        tracks[i].volume   = PositionGetDouble(POSITION_VOLUME);
      }
  }
}

bool FillEntryFromHistory(const ulong position_id,
                          datetime &open_time,
                          double &entry_price,
                          double &volume,
                          string &side,
                          double &sl_price,
                          double &tp_price)
{
  // Select a reasonable window (same as sync window, plus buffer)
  datetime to_time = TimeCurrent();
  datetime from_time = to_time - (datetime)(365 * 86400); // 1 year
  HistorySelect(from_time, to_time);

  int total = HistoryDealsTotal();
  if(total <= 0) return false;

  // Find earliest entry deal for this position
  bool found = false;
  datetime best_time = 0;
  ulong best_deal = 0;

  for(int i = 0; i < total; i++)
  {
    ulong deal = HistoryDealGetTicket(i);
    if(deal == 0) continue;
    if(!HistoryDealSelect(deal)) continue;

    ulong pid = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
    if(pid != position_id) continue;

    long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
    if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;

    datetime t = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
    if(!found || t < best_time)
    {
      found = true;
      best_time = t;
      best_deal = deal;
    }
  }

  if(!found || best_deal == 0) return false;
  if(!HistoryDealSelect(best_deal)) return false;

  open_time   = (datetime)HistoryDealGetInteger(best_deal, DEAL_TIME);
  entry_price = HistoryDealGetDouble(best_deal, DEAL_PRICE);
  volume      = HistoryDealGetDouble(best_deal, DEAL_VOLUME);

  long dtype = HistoryDealGetInteger(best_deal, DEAL_TYPE);
  side = (dtype == DEAL_TYPE_SELL) ? "SELL" : "BUY";

  // SL/TP: deals don't reliably store SL/TP. Keep previous values if already set.
  // If you want accurate SL/TP historically, you'd need order history or store them on entry in real-time.
  // So we only keep what we already have.
  // sl_price and tp_price passed by ref so caller can keep existing.

  return true;
}


// -------------------- Build JSON payload (your schema) --------------------
string BuildPayloadFromDeal(ulong deal_id, ulong position_identifier)
{
  if(!HistoryDealSelect(deal_id)) return "";

  string sym = (string)HistoryDealGetString(deal_id, DEAL_SYMBOL);
  if(StringLen(sym) == 0) return "";
  int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

  // Close deal info
  datetime close_time = (datetime)HistoryDealGetInteger(deal_id, DEAL_TIME);
  double close_price  = HistoryDealGetDouble(deal_id, DEAL_PRICE);
  double pnl          = HistoryDealGetDouble(deal_id, DEAL_PROFIT);
  double commission   = HistoryDealGetDouble(deal_id, DEAL_COMMISSION);
  double swap         = HistoryDealGetDouble(deal_id, DEAL_SWAP);
  double net_pnl      = pnl + commission + swap;

  // Defaults (will be filled)
  string side = "BUY";
  double volume = 0.0;
  double entry_price = 0.0;
  datetime open_time = 0;
  double sl_price = 0.0;
  double tp_price = 0.0;
  double mae_points = 0.0;
  double mfe_points = 0.0;

  double mae_cash = 0.0;
  double mfe_cash = 0.0;
  double dd_pct   = 0.0;


  // 1) Prefer tracker (near-perfect MAE/MFE)
  int idx = FindTrackByIdentifier(position_identifier);
  if(idx >= 0)
  {
    side        = (tracks[idx].side == POSITION_TYPE_BUY) ? "BUY" : "SELL";
    volume      = tracks[idx].volume;
    entry_price = tracks[idx].entry_price;
    open_time   = tracks[idx].entry_time;
    sl_price    = tracks[idx].sl_price;
    tp_price    = tracks[idx].tp_price;
    mae_points  = tracks[idx].mae_points;
    mfe_points  = tracks[idx].mfe_points;
    mfe_cash = tracks[idx].mfe_cash_live;
    mae_cash = tracks[idx].mae_cash_live;

    if(tracks[idx].entry_balance > 0.0)
      dd_pct = (mae_cash / tracks[idx].entry_balance) * 100.0;
  }

  // 2) If tracker missing OR any critical fields still empty, recover from history
  if(open_time == 0 || entry_price == 0.0 || volume == 0.0)
  {
    datetime ot = 0;
    double ep = 0.0, vol = 0.0;
    string sd = side;

    double sl_tmp = sl_price;
    double tp_tmp = tp_price;

    if(FillEntryFromHistory(position_identifier, ot, ep, vol, sd, sl_tmp, tp_tmp))
    {
      if(open_time == 0)   open_time = ot;
      if(entry_price == 0) entry_price = ep;
      if(volume == 0.0)    volume = vol;
      side = sd;
      // sl/tp remain best-effort; deals don't reliably contain them
    }
  }

  // 3) Absolute safety: never send empty open_time (prevents validation failures)
  if(open_time == 0) open_time = close_time;

  // Cash calculations
  double risk_points = 0.0;
  if(sl_price > 0.0 && entry_price > 0.0)
    risk_points = PointsBetween(sym, entry_price, sl_price);

  // If live cash DD wasn't available (e.g., SYNC/backfill), fall back to points->cash (may be 0 on synthetics)
  if(mae_cash <= 0.0)
    mae_cash = CashFromPoints(sym, mae_points, volume);

  double risk_cash = CashFromPoints(sym, risk_points, volume);

  string setup = DEFAULT_SETUP;
  string notes = "";

  double balance = AccountInfoDouble(ACCOUNT_BALANCE);
  double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

  string sym_norm = NormalizeSymbol(sym);

  // Optional debug
  if(open_time == 0)
    Log("WARN open_time=0 deal_id=" + (string)deal_id + " pos_ident=" + (string)position_identifier);

  string json =
    "{"
      "\"deal_id\":\"" + (string)deal_id + "\","
      "\"account_id\":\"" + JsonEscape(GetAccountId()) + "\","
      "\"broker\":\"" + JsonEscape(BROKER_NAME) + "\","
      "\"symbol\":\"" + JsonEscape(sym_norm) + "\","
      "\"side\":\"" + JsonEscape(side) + "\","
      "\"volume\":" + DoubleToString(volume, 2) + ","
      "\"entry_price\":" + DoubleToString(entry_price, digits) + ","
      "\"close_price\":" + DoubleToString(close_price, digits) + ","
      "\"sl_price\":" + DoubleToString(sl_price, digits) + ","
      "\"tp_price\":" + DoubleToString(tp_price, digits) + ","
      "\"open_time\":\"" + ToIso8601UTC(open_time) + "\","
      "\"close_time\":\"" + ToIso8601UTC(close_time) + "\","
      "\"pnl\":" + DoubleToString(pnl, 2) + ","
      "\"commission\":" + DoubleToString(commission, 2) + ","
      "\"swap\":" + DoubleToString(swap, 2) + ","
      "\"net_pnl\":" + DoubleToString(net_pnl, 2) + ","
      "\"mae\":" + DoubleToString(mae_points, 2) + ","
      "\"mae_cash\":" + DoubleToString(mae_cash, 2) + ","
      "\"mfe\":" + DoubleToString(mfe_points, 2) + ","
      "\"risk\":" + DoubleToString(risk_points, 2) + ","
      "\"risk_cash\":" + DoubleToString(risk_cash, 2) + ","
      "\"balance\":" + DoubleToString(balance, 2) + ","
      "\"equity\":" + DoubleToString(equity, 2);

  if(StringLen(setup) > 0)
    json += ",\"setup\":\"" + JsonEscape(setup) + "\"";
  if(StringLen(notes) > 0)
    json += ",\"notes\":\"" + JsonEscape(notes) + "\"";

  json += "}";

  return json;
}


// -------------------- Transaction hook --------------------
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
  // Keep tracker in sync
  if(trans.type == TRADE_TRANSACTION_POSITION && trans.position > 0)
    EnsureTrackForPosition(trans.position);

  // Deal added -> check if it's a close/partial close
  if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
  {
    ulong deal_id = trans.deal;
    ulong position_identifier = (ulong)HistoryDealGetInteger(deal_id, DEAL_POSITION_ID);
    ulong position_ticket     = trans.position; // keep for removal check


    if(!HistoryDealSelect(deal_id)) return;

    long entry = HistoryDealGetInteger(deal_id, DEAL_ENTRY);
    bool is_close = (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT);

    if(!is_close) return;

    string payload = BuildPayloadFromDeal(deal_id, position_identifier);
    Log("WHOLE_BODY=" + payload);
    if(StringLen(payload) == 0) return;

    string resp_headers, resp_body; int code=0;
    bool ok = PostJson(Url(), payload, resp_headers, resp_body, code);

    Log("HTTP=" + IntegerToString(code));
    Log("RESP_BODY=" + resp_body);     // <-- THIS will show the real error
    // (Optional) Log headers too if you want:
    // Log("RESP_HEADERS=" + resp_headers);

    if(!ok) QueueAppend(payload);




    // If position no longer exists, stop tracking it
    if(!PositionSelectByTicket(position_ticket))
    {
      int idx = FindTrackByIdentifier(position_identifier);
      if(idx >= 0) RemoveTrack(idx);
    }
  }
}

// -------------------- Lifecycle --------------------
int OnInit()
{
  EventSetTimer(RETRY_TIMER_SECONDS);

  // create UI button
  CreateTestButton();

  // rebuild tracking for currently open positions (restart safe)
  int total = PositionsTotal();
  for(int i=0;i<total;i++)
  {
    ulong pos = PositionGetTicket(i);
    if(pos > 0) EnsureTrackForPosition(pos);
  }

  g_last_status = "Ready";
  UpdateStatus();
  Log("EA initialized. URL=" + Url());

  return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
  EventKillTimer();
  ObjectDelete(0, BTN_NAME);
  Comment("");
  Log("EA stopped. reason=" + IntegerToString(reason));
}

void OnTick()
{
  UpdateTracksOnTick();
}

void OnTimer()
{
  FlushQueue();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
  if(id == CHARTEVENT_OBJECT_CLICK && sparam == BTN_NAME)
  {
    if(g_sync_in_progress) return;

    Log("Button clicked: SYNC DATA");

    g_sync_in_progress = true;
    SyncHistory();
    g_sync_in_progress = false;
  }
}
