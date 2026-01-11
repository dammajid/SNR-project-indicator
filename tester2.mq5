//+------------------------------------------------------------------+
//|                                    XAUUSD_OB_BB_EA_V4_Optimized.mq5 |
//|                                    Algorithmic Trading Developer  |
//+------------------------------------------------------------------+
#property copyright "Algorithmic Trading Developer"
#property version   "1.07"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input double InpRiskPercent      = 1.0;      // Risk per trade (%)
input double InpFixedLot         = 0.0;      // Fixed Lot (0 = use Risk %)
input int    InpStopLossBuffer   = 30;       // SL Buffer (Points)
input int    InpMagicNum         = 123456;   // Magic Number
input int    InpMaxSpread        = 50;       // Max Spread (Points)
input int    InpOB_Lookback      = 150;      // Bars to look back for OBs
input int    InpBB_Period        = 20;       // Bollinger Bands Period
input double InpBB_Dev           = 2.0;      // Bollinger Bands Deviation
input bool   InpShowVisuals      = true;     // Show Order Block Boxes

// FREQUENCY OPTIMIZATION SETTINGS
input int    InpMaxTradesPerSession = 3;     // Max Trades allowed per Session (0 = Unlimited)
input int    InpOB_Expansion       = 100;    // EXPAND OB ZONE (Points) - Helps price enter the zone
input int    InpCooldownMinutes    = 30;     // Minutes to wait after a trade before taking another

// FILTER SETTINGS
input bool   InpRespectSessionBias = true;    // TRUE = Strict Filter (H1 Rule), FALSE = Ignore Bias
input bool   InpVerboseLogs      = true;     // Print status in Experts tab
input bool   InpBypassBBFilter   = false;    // TRUE = Ignore BB check (More entries)

// Session Inputs (Server Time - usually GMT+2/+3)
input int    InpLondonStart      = 7;        // London Start Hour
input int    InpLondonEnd        = 11;       // London End Hour
input int    InpNYStart          = 12;       // New York Start Hour
input int    InpNYEnd            = 16;       // New York End Hour

//--- Global Variables
CTrade trade;

// Indikator Handles
int h_H1_EMA;        
int h_M5_BB;         

// Indikator Buffers
double h1_ema_val[];
double m5_bb_upper[];
double m5_bb_lower[];

// Price Data Arrays
MqlRates m5_rates[]; 
MqlRates h1_rates[]; 

// Bias Management
enum ENUM_BIAS { BIAS_NONE, BIAS_BUY, BIAS_SELL };
ENUM_BIAS g_sessionBias = BIAS_NONE;
datetime g_lastSessionDay = 0;
int g_tradesCountSession = 0;
datetime g_lastTradeTime = 0;

// Order Block Structure
struct OrderBlock {
    datetime time;
    double price_high;
    double price_low;
    bool is_bullish; 
    bool is_active;
    string obj_name;
};
OrderBlock g_ob_list[];

// Trade Management
// Removed: g_tradeTakenThisSession (Replaced with counter)

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagicNum);
    
    h_H1_EMA = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
    if(h_H1_EMA == INVALID_HANDLE) {
        Print("Error creating H1 EMA handle");
        return(INIT_FAILED);
    }
    
    h_M5_BB = iBands(_Symbol, PERIOD_M5, InpBB_Period, 0, InpBB_Dev, PRICE_CLOSE);
    if(h_M5_BB == INVALID_HANDLE) {
        Print("Error creating M5 BB handle");
        return(INIT_FAILED);
    }
    
    ArraySetAsSeries(h1_ema_val, true);
    ArraySetAsSeries(m5_bb_upper, true);
    ArraySetAsSeries(m5_bb_lower, true);
    ArraySetAsSeries(m5_rates, true);
    ArraySetAsSeries(h1_rates, true);
    
    ArrayResize(g_ob_list, InpOB_Lookback);
    
    for(int i=0; i<InpOB_Lookback; i++) {
        g_ob_list[i].time = 0;
        g_ob_list[i].is_active = false;
    }
    
    Print("EA V4 Initialized. Optimized for Frequency.");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(h_H1_EMA);
    IndicatorRelease(h_M5_BB);
    ObjectsDeleteAll(0, "OB_"); 
    Comment(""); 
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
    if(CopyRates(_Symbol, PERIOD_M5, 0, InpOB_Lookback + 5, m5_rates) < 10) return;
    if(CopyRates(_Symbol, PERIOD_H1, 0, 5, h1_rates) < 5) return;

    if(!IsSessionActive()) {
        Comment("Market CLOSED / Outside Session");
        return;
    }
    if(!IsSpreadAcceptable()) {
        Comment("Spread too HIGH");
        return;
    }
    
    ManageOpenTrades();
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Reset Logic on New Day
    if(dt.day != g_lastSessionDay) {
        g_sessionBias = BIAS_NONE; 
        g_tradesCountSession = 0;
        g_lastSessionDay = dt.day;
        if(InpVerboseLogs) Print("New Day Detected. Counters Reset.");
    }
    // Reset Logic on New Session (London to NY transition) - Simple Approximation
    // If hour is 12 (NY Start), reset counter if we want separate session limits
    if(dt.hour == InpNYStart && g_tradesCountSession > 0) {
        g_tradesCountSession = 0;
        Print("New Session Started. Counter Reset.");
    }
    
    // Check Limit
    if(InpMaxTradesPerSession > 0 && g_tradesCountSession >= InpMaxTradesPerSession) {
        Comment("Max Trades per Session Reached.");
        return;
    }
    
    // Check Cooldown
    if(InpCooldownMinutes > 0 && (TimeCurrent() - g_lastTradeTime) < (InpCooldownMinutes * 60)) {
        Comment("Cooldown Period. Waiting...");
        return;
    }
    
    // H1 Bias
    if(InpRespectSessionBias) {
        DetermineH1Bias();
    }
    
    static datetime lastBarTime = 0;
    datetime currentBarTime = m5_rates[0].time; 
    
    if(currentBarTime != lastBarTime) {
        DetectOrderBlocks();
        ValidateOrderBlocks();
        DrawVisuals(); 
        lastBarTime = currentBarTime;
    }
    
    if(PositionsTotal() == 0) {
        CheckEntrySignal_Debug();
    } else {
        Comment("Position Open.");
    }
}

//+------------------------------------------------------------------+
//| Helper: Session & Spread                                          |
//+------------------------------------------------------------------+
bool IsSessionActive()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int hour = dt.hour;
    bool london = (hour >= InpLondonStart && hour < InpLondonEnd);
    bool ny = (hour >= InpNYStart && hour < InpNYEnd);
    return (london || ny);
}
bool IsSpreadAcceptable()
{
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    return (spread <= InpMaxSpread);
}

//+------------------------------------------------------------------+
//| Logic: Determine H1 Bias                                          |
//+------------------------------------------------------------------+
void DetermineH1Bias()
{
    if(g_sessionBias != BIAS_NONE) return;
    if(CopyBuffer(h_H1_EMA, 0, 0, 3, h1_ema_val) < 3) return;
    
    double close1 = h1_rates[1].close;
    double ema_curr = h1_ema_val[0];
    
    if(close1 > ema_curr) {
        g_sessionBias = BIAS_BUY;
        Print("H1 BIAS set to BUY (Price > EMA).");
    }
    else if(close1 < ema_curr) {
        g_sessionBias = BIAS_SELL;
        Print("H1 BIAS set to SELL (Price < EMA).");
    }
}

//+------------------------------------------------------------------+
//| Logic: Detect Order Blocks (M5)                                   |
//+------------------------------------------------------------------+
void DetectOrderBlocks()
{
    for(int i = 3; i < InpOB_Lookback; i++) {
        double impClose = m5_rates[i].close;
        double impOpen = m5_rates[i].open;
        double impHigh = m5_rates[i].high;
        double impLow  = m5_rates[i].low;
        
        double prevClose = m5_rates[i+1].close;
        double prevOpen  = m5_rates[i+1].open;
        double prevHigh  = m5_rates[i+1].high;
        double prevLow   = m5_rates[i+1].low;
        
        datetime obTime = m5_rates[i+1].time;
        
        bool exists = false;
        for(int k=0; k<InpOB_Lookback; k++) {
            if(g_ob_list[k].time == obTime) exists = true;
        }
        if(exists) continue;
        
        // Bullish OB
        bool strongBullImpulse = (impClose > impOpen) && (impHigh > m5_rates[i+2].high);
        bool prevBearish = (prevClose < prevOpen);
        
        if(strongBullImpulse && prevBearish) {
            AddOB(i+1, prevHigh, prevLow, true); 
            continue; 
        }
        
        // Bearish OB
        bool strongBearImpulse = (impClose < impOpen) && (impLow < m5_rates[i+2].low);
        bool prevBullish = (prevClose > prevOpen);
        
        if(strongBearImpulse && prevBullish) {
            AddOB(i+1, prevHigh, prevLow, false); 
        }
    }
}

//+------------------------------------------------------------------+
//| Helper: Add OB                                                     |
//+------------------------------------------------------------------+
void AddOB(int index, double high, double low, bool isBullish) {
    for(int k=0; k<InpOB_Lookback; k++) {
        if(g_ob_list[k].time == 0) {
            g_ob_list[k].time = m5_rates[index].time;
            g_ob_list[k].price_high = high;
            g_ob_list[k].price_low = low;
            g_ob_list[k].is_bullish = isBullish;
            g_ob_list[k].is_active = true;
            g_ob_list[k].obj_name = "OB_" + IntegerToString(k);
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Logic: Validate/Mitigate Order Blocks                              |
//+------------------------------------------------------------------+
void ValidateOrderBlocks()
{
    for(int i=0; i<InpOB_Lookback; i++) {
        if(g_ob_list[i].time == 0) continue;
        if(!g_ob_list[i].is_active) continue;
        
        double lastClose = m5_rates[1].close;
        
        if(g_ob_list[i].is_bullish) {
            if(lastClose < g_ob_list[i].price_low) g_ob_list[i].is_active = false; 
        } else {
            if(lastClose > g_ob_list[i].price_high) g_ob_list[i].is_active = false; 
        }
    }
}

//+------------------------------------------------------------------+
//| Logic: Visualize OBs (Include Expansion)                           |
//+------------------------------------------------------------------+
void DrawVisuals()
{
    if(!InpShowVisuals) return;
    
    for(int i=0; i<InpOB_Lookback; i++) {
        if(g_ob_list[i].time == 0) continue;
        
        color clr = (g_ob_list[i].is_bullish) ? clrDodgerBlue : clrCrimson;
        int width = (g_ob_list[i].is_active) ? 2 : 1;
        long style = (g_ob_list[i].is_active) ? STYLE_SOLID : STYLE_DOT;
        
        // Visualizing the EXPANDED zone
        double expansionPoints = InpOB_Expansion * _Point;
        double visHigh = g_ob_list[i].price_high + expansionPoints;
        double visLow = g_ob_list[i].price_low - expansionPoints;
        
        datetime endTime = g_ob_list[i].time + PeriodSeconds(PERIOD_M5) * 20; 
        
        if(ObjectFind(0, g_ob_list[i].obj_name) >= 0) {
            ObjectDelete(0, g_ob_list[i].obj_name);
        }
        
        ObjectCreate(0, g_ob_list[i].obj_name, OBJ_RECTANGLE, 0, g_ob_list[i].time, visHigh, endTime, visLow);
        ObjectSetInteger(0, g_ob_list[i].obj_name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, g_ob_list[i].obj_name, OBJPROP_FILL, true);
        ObjectSetInteger(0, g_ob_list[i].obj_name, OBJPROP_BACK, true);
        ObjectSetInteger(0, g_ob_list[i].obj_name, OBJPROP_STYLE, style);
        ObjectSetInteger(0, g_ob_list[i].obj_name, OBJPROP_WIDTH, width);
    }
}

//+------------------------------------------------------------------+
//| Logic: Check Entry Signal (With Expansion)                         |
//+------------------------------------------------------------------+
void CheckEntrySignal_Debug()
{
    if(CopyBuffer(h_M5_BB, 1, 0, 2, m5_bb_upper) < 2) return;
    if(CopyBuffer(h_M5_BB, 2, 0, 2, m5_bb_lower) < 2) return;
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double prevClose = m5_rates[1].close;
    
    string debugText = "=== DEBUG STATUS V4 ===\n";
    
    if(InpRespectSessionBias) {
        debugText += "Bias: " + EnumToString(g_sessionBias) + "\n";
        if(g_sessionBias == BIAS_NONE) {
            debugText += "[WAITING FOR BIAS...]\n";
            Comment(debugText);
            return;
        }
    } else {
        debugText += "Bias: DISABLED\n";
    }
    
    debugText += "Session Trades: " + IntegerToString(g_tradesCountSession) + "/" + IntegerToString(InpMaxTradesPerSession) + "\n";
    
    bool foundCandidate = false;
    string failReason = "";
    
    for(int i=0; i<InpOB_Lookback; i++) {
        if(g_ob_list[i].time == 0) continue;
        if(!g_ob_list[i].is_active) continue;
        
        if(!foundCandidate) {
            foundCandidate = true;
            
            // CALCULATE EXPANDED ZONE
            double expansion = InpOB_Expansion * _Point;
            double zoneHigh = g_ob_list[i].price_high + expansion;
            double zoneLow  = g_ob_list[i].price_low - expansion;
            
            // 1. Bias Check
            bool biasOk = true;
            if(InpRespectSessionBias) {
                if(g_ob_list[i].is_bullish && g_sessionBias != BIAS_BUY) biasOk = false;
                if(!g_ob_list[i].is_bullish && g_sessionBias != BIAS_SELL) biasOk = false;
            }
            
            debugText += "1. Bias Match: " + (biasOk ? "YES" : "NO") + "\n";
            if(!biasOk) { failReason = "Bias Mismatch"; continue; }
            
            // 2. Check EXPANDED Zone & Retrace
            bool insideZone = false;
            double penetration = 0;
            double obHeight = zoneHigh - zoneLow; // Use expanded height for retrace calc
            
            if(g_ob_list[i].is_bullish) {
                insideZone = (ask >= zoneLow && ask <= zoneHigh);
                penetration = (ask - zoneLow) / obHeight;
            } else {
                insideZone = (bid <= zoneHigh && bid >= zoneLow);
                penetration = (zoneHigh - bid) / obHeight;
            }
            
            bool retraceOk = (penetration >= 0.5);
            
            debugText += "2. In Expanded Zone: " + (insideZone ? "YES" : "NO") + "\n";
            if(!insideZone) { failReason = "Price not in Expanded Zone"; continue; }
            
            debugText += "   Retrace: " + DoubleToString(penetration*100, 1) + "%\n";
            if(!retraceOk) { failReason = "Retrace < 50%"; continue; }
            
            // 3. BB Confirmation
            bool bbOk = false;
            if(g_ob_list[i].is_bullish) {
                bbOk = (prevClose <= m5_bb_lower[1]);
                debugText += "   BB Check: " + (bbOk ? "PASS" : "FAIL") + "\n";
            } else {
                bbOk = (prevClose >= m5_bb_upper[1]);
                debugText += "   BB Check: " + (bbOk ? "PASS" : "FAIL") + "\n";
            }
            
            if(InpBypassBBFilter) {
                debugText += "   [BB FILTER BYPASSED]\n";
                bbOk = true;
            }
            
            if(!bbOk) { failReason = "BB Condition Failed"; continue; }
            
            // EXECUTE
            debugText += "\n>>> EXECUTING TRADE! <<<";
            Comment(debugText);
            
            // Calculate SL based on REAL OB (Not expanded)
            if(g_ob_list[i].is_bullish) {
                double sl = g_ob_list[i].price_low - (InpStopLossBuffer * _Point);
                ExecuteTrade(i, true, ask, sl, obHeight);
            } else {
                double sl = g_ob_list[i].price_high + (InpStopLossBuffer * _Point);
                ExecuteTrade(i, false, bid, sl, obHeight);
            }
            return;
        }
    }
    
    if(!foundCandidate) {
        debugText += "No Active OB found near price.";
    } else {
        debugText += "\n[STATUS]: ENTRY FAILED\nReason: " + failReason;
    }
    
    Comment(debugText);
}

//+------------------------------------------------------------------+
//| Execute Trade                                                      |
//+------------------------------------------------------------------+
void ExecuteTrade(int obIndex, bool isBuy, double entry, double sl, double riskDist)
{
    double tp = (isBuy) ? entry + (riskDist * 2.0) : entry - (riskDist * 2.0);
    double lots = InpFixedLot;
    if(lots == 0.0) lots = CalculateLotSize(riskDist);
    
    if(isBuy) {
        if(trade.Buy(lots, _Symbol, entry, sl, tp, "OB_Buy")) {
            Print("Order BUY Placed.");
            g_tradesCountSession++;
            g_lastTradeTime = TimeCurrent();
            g_ob_list[obIndex].is_active = false;
        }
    } else {
        if(trade.Sell(lots, _Symbol, entry, sl, tp, "OB_Sell")) {
            Print("Order SELL Placed.");
            g_tradesCountSession++;
            g_lastTradeTime = TimeCurrent();
            g_ob_list[obIndex].is_active = false;
        }
    }
}

//+------------------------------------------------------------------+
//| Helper: Calculate Lot Size                                        |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskValue = accountBalance * (InpRiskPercent / 100.0);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tickSize == 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    double points = slDistance / tickSize;
    if(points == 0) return minLot;
    
    double lots = riskValue / (points * tickValue);
    lots = MathFloor(lots / lotStep) * lotStep;
    if(lots < minLot) lots = minLot;
    if(lots > maxLot) lots = maxLot;
    return lots;
}

//+------------------------------------------------------------------+
//| Manage Open Trades                                                 |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetInteger(POSITION_MAGIC) != InpMagicNum) continue;
            
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl = PositionGetDouble(POSITION_SL);
            double tp = PositionGetDouble(POSITION_TP);
            double currentPrice = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                                  SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                  SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            
            double riskDist = MathAbs(openPrice - sl);
            double profitDist = 0;
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                profitDist = currentPrice - openPrice;
                if(profitDist >= riskDist && sl < openPrice) {
                    trade.PositionModify(ticket, openPrice + (10 * _Point), tp);
                }
                else if(profitDist >= (riskDist * 1.5)) {
                    double newSL = currentPrice - (riskDist * 0.5);
                    if(newSL > sl + (10*_Point)) 
                        trade.PositionModify(ticket, newSL, tp);
                }
            } 
            else { // SELL
                profitDist = openPrice - currentPrice;
                if(profitDist >= riskDist && (sl > openPrice || sl == 0)) {
                    trade.PositionModify(ticket, openPrice - (10 * _Point), tp);
                }
                else if(profitDist >= (riskDist * 1.5)) {
                    double newSL = currentPrice + (riskDist * 0.5);
                    if(newSL < sl - (10*_Point) || sl == 0)
                        trade.PositionModify(ticket, newSL, tp);
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
