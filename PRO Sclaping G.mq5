//+------------------------------------------------------------------+
//|                                  XAUUSD Pullback Trader EA       |
//|                                  Trend Continuation Strategy     |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property version   "4.00"
#property description "Pullback Trading - Entry on trend continuation"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Global Objects
CTrade trade;
CPositionInfo position;
string CurrentSymbol = _Symbol;
ENUM_TIMEFRAMES EntryTF = PERIOD_M15;
ENUM_TIMEFRAMES TrendTF = PERIOD_H1;

//--- Input Parameters
input group "=== Risk Management ==="
input bool   UseFixedLot     = true;      // Use Fixed Lot (true) or Risk % (false)
input double FixedLotSize    = 0.01;      // Fixed Lot Size (jika UseFixedLot = true)
input double RiskPercent     = 3.0;       // Risk per trade % (jika UseFixedLot = false)
input int    StopLossPips    = 200;       // Stop Loss in pips (wide like Beatrix)
input int    TakeProfitPips  = 0;         // Take Profit (0 = no fixed TP, use trailing only)
input int    TrailingStart   = 20;        // Trailing start pips (AGGRESSIVE!)
input int    TrailingStop    = 15;        // Trailing stop pips (TIGHT!)
input int    BreakEvenPips   = 30;        // Break even after X pips

input group "=== Pullback Settings ==="
input int    EMA_Fast        = 20;        // Fast EMA (M15)
input int    EMA_Slow        = 50;        // Slow EMA (M15)
input int    EMA_Trend       = 100;       // Trend EMA (H1)
input double PullbackZone    = 40;        // Max distance from EMA (pips)
input int    MinBarsSince    = 2;         // Min bars between entries (allow pyramiding)

input group "=== Pyramiding (Multiple Entries) ==="
input bool   UsePyramiding   = true;      // Enable pyramiding (add positions in trend)
input int    MaxPositions    = 3;         // Max positions at once (like Beatrix)
input int    PyramidStep     = 30;        // Add position every X pips profit

input group "=== Trade Management ==="
input int    MagicNumber     = 144406;    // Magic Number
input int    MaxDailyTrades  = 10;        // Max trades per day
input double MaxDailyLossPct = 5.0;       // Max daily loss %

input group "=== paramater summry ==="
input bool  UsePartialClose = true;
input double PartialClosePercent = 50.0;
input int    PartialCloseAtPips  = 60;



//--- Global Handles
int fast_ema_handle;
int slow_ema_handle;
int h1_ema_handle;

//--- Global Variables
datetime last_trade_time = 0;
datetime daily_reset_time = 0;
double daily_profit = 0.0;
int daily_trades = 0;

//--- Dashboard Variables
string dashboard_name = "EA_Dashboard";
int corner_position = CORNER_LEFT_UPPER;
int x_distance = 20;
int y_distance = 50;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if (CurrentSymbol != "XAUUSD" && CurrentSymbol != "XAUUSDm")
   {
      Print("WARNING: Optimized for XAUUSD");
   }
   
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(50);
   
   //--- Create indicators
   fast_ema_handle = iMA(CurrentSymbol, EntryTF, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   slow_ema_handle = iMA(CurrentSymbol, EntryTF, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   h1_ema_handle = iMA(CurrentSymbol, TrendTF, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   
   if (fast_ema_handle == INVALID_HANDLE || slow_ema_handle == INVALID_HANDLE || 
       h1_ema_handle == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return(INIT_FAILED);
   }
   
   Print("=== Pullback Trader Initialized ===");
   Print("Strategy: Pullback to EMA in trend | TF: M15 | Trend: H1");
   
   //--- Create dashboard
   CreateDashboard();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (fast_ema_handle != INVALID_HANDLE) IndicatorRelease(fast_ema_handle);
   if (slow_ema_handle != INVALID_HANDLE) IndicatorRelease(slow_ema_handle);
   if (h1_ema_handle != INVALID_HANDLE) IndicatorRelease(h1_ema_handle);
   
   //--- Delete dashboard
   DeleteDashboard();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime last_bar = 0;
   datetime current_bar = iTime(CurrentSymbol, EntryTF, 0);
   
   if (current_bar == last_bar) return;
   last_bar = current_bar;
   
   //--- Reset daily stats
   CheckDailyReset();
   
   //--- Check daily limits
   if (daily_trades >= MaxDailyTrades) return;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if (daily_profit <= -(balance * MaxDailyLossPct / 100.0)) return;
   
   //--- Manage existing positions
   ManagePositions();
   
   //--- Check if can open new trade
   int open_positions = CountOpenPositions();
   
   // Allow pyramiding if enabled
   if (open_positions >= MaxPositions) return;
   
   // Check for pyramiding opportunity
   if (open_positions > 0 && UsePyramiding)
   {
      CheckPyramidingOpportunity();
   }
   
   // Check for new initial entry
   if (open_positions == 0)
   {
      //--- Check minimum bars between entries
      int bars_since = (int)((TimeCurrent() - last_trade_time) / PeriodSeconds(EntryTF));
      if (bars_since < MinBarsSince && last_trade_time > 0) return;
      
      //--- Look for pullback signals
      CheckPullbackSignals();
   }
   
   //--- Update display
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Check for Pullback Signals                                       |
//+------------------------------------------------------------------+
void CheckPullbackSignals()
{
   //--- Get H1 Trend EMA
   double h1_ema[];
   ArraySetAsSeries(h1_ema, true);
   if (CopyBuffer(h1_ema_handle, 0, 0, 3, h1_ema) < 3) return;
   
   double h1_close = iClose(CurrentSymbol, TrendTF, 1);
   
   // Determine H1 trend
   bool h1_bullish = (h1_close > h1_ema[1]);
   bool h1_bearish = (h1_close < h1_ema[1]);
   
   //--- Get M15 EMAs
   double fast_ema[], slow_ema[];
   ArraySetAsSeries(fast_ema, true);
   ArraySetAsSeries(slow_ema, true);
   if (CopyBuffer(fast_ema_handle, 0, 0, 5, fast_ema) < 5) return;
   if (CopyBuffer(slow_ema_handle, 0, 0, 5, slow_ema) < 5) return;
   
   //--- Get price data
   double high[], low[], close[], open[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open, true);
   
   if (CopyHigh(CurrentSymbol, EntryTF, 0, 5, high) < 5) return;
   if (CopyLow(CurrentSymbol, EntryTF, 0, 5, low) < 5) return;
   if (CopyClose(CurrentSymbol, EntryTF, 0, 5, close) < 5) return;
   if (CopyOpen(CurrentSymbol, EntryTF, 0, 5, open) < 5) return;
   
   double point = SymbolInfoDouble(CurrentSymbol, SYMBOL_POINT);
   
   //--- BUY Pullback Setup
   if (h1_bullish && fast_ema[1] > slow_ema[1])
   {
      // Check if price pulled back to Fast EMA
      double distance_to_ema = MathAbs(close[1] - fast_ema[1]) / (point * 10);
      
      if (distance_to_ema <= PullbackZone)
      {
         // Check for bullish rejection
         bool bullish_candle = (close[1] > open[1]);
         bool bouncing_up = (close[1] > close[2]);
         bool lower_wick = (MathMin(open[1], close[1]) - low[1]) > (close[1] - open[1]);
         
         if ((bullish_candle || bouncing_up) && close[1] > fast_ema[1])
         {
            Print(">>> BUY Pullback Signal <<<");
            Print("H1 Trend: BULLISH | Distance to EMA: ", DoubleToString(distance_to_ema, 1), " pips");
            Print("Price: ", close[1], " | Fast EMA: ", fast_ema[1]);
            OpenTrade(ORDER_TYPE_BUY);
            return;
         }
      }
   }
   
   //--- SELL Pullback Setup
   if (h1_bearish && fast_ema[1] < slow_ema[1])
   {
      // Check if price pulled back to Fast EMA
      double distance_to_ema = MathAbs(close[1] - fast_ema[1]) / (point * 10);
      
      if (distance_to_ema <= PullbackZone)
      {
         // Check for bearish rejection
         bool bearish_candle = (close[1] < open[1]);
         bool bouncing_down = (close[1] < close[2]);
         bool upper_wick = (high[1] - MathMax(open[1], close[1])) > (open[1] - close[1]);
         
         if ((bearish_candle || bouncing_down) && close[1] < fast_ema[1])
         {
            Print(">>> SELL Pullback Signal <<<");
            Print("H1 Trend: BEARISH | Distance to EMA: ", DoubleToString(distance_to_ema, 1), " pips");
            Print("Price: ", close[1], " | Fast EMA: ", fast_ema[1]);
            OpenTrade(ORDER_TYPE_SELL);
            return;
         }
      }
   }
   
   //--- Debug output every 20 bars
   static int debug_counter = 0;
   debug_counter++;
   if (debug_counter >= 20)
   {
      debug_counter = 0;
      Print("=== Status ===");
      Print("H1 Trend: ", (h1_bullish ? "BULLISH" : "BEARISH"));
      Print("M15 EMA: Fast=", DoubleToString(fast_ema[1], 2), " Slow=", DoubleToString(slow_ema[1], 2));
      Print("Close: ", close[1], " | Distance: ", DoubleToString(MathAbs(close[1] - fast_ema[1])/(point*10), 1), " pips");
   }
}

//+------------------------------------------------------------------+
//| Open Trade with Risk Management                                  |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE order_type)
{
   double point = SymbolInfoDouble(CurrentSymbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(CurrentSymbol, SYMBOL_DIGITS);
   
   // XAUUSD: 1 pip = 10 points (karena 3 digit)
   double pip_value = (digits == 3 || digits == 5) ? 10 : 1;
   
   //--- Calculate lot size
   double lot_size;
   
   if (UseFixedLot)
   {
      // Gunakan fixed lot
      lot_size = FixedLotSize;
      Print("Using Fixed Lot: ", lot_size);
   }
   else
   {
      // Calculate lot based on risk %
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double risk_money = balance * (RiskPercent / 100.0);
      double tick_value = SymbolInfoDouble(CurrentSymbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(CurrentSymbol, SYMBOL_TRADE_TICK_SIZE);
      
      double sl_distance = StopLossPips * pip_value * point;
      lot_size = risk_money / ((StopLossPips * pip_value) * tick_value / tick_size);
      Print("Calculated Lot from Risk ", RiskPercent, "%: ", lot_size);
   }
   
   //--- Normalize lot
   double min_lot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_STEP);
   
   lot_size = MathFloor(lot_size / step_lot) * step_lot;
   lot_size = NormalizeDouble(lot_size, 2);
   
   if (lot_size < min_lot) lot_size = min_lot;
   if (lot_size > max_lot) lot_size = max_lot;
   
   //--- Get entry price
   double price = (order_type == ORDER_TYPE_BUY) ? 
                  SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK) : 
                  SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
   
   //--- Calculate SL and TP dengan benar
   double sl, tp;
   if (order_type == ORDER_TYPE_BUY)
   {
      sl = price - (StopLossPips * pip_value * point);      // Wide SL
      
      // TP: if 0, no fixed TP (use trailing only)
      if (TakeProfitPips > 0)
         tp = price + (TakeProfitPips * pip_value * point);
      else
         tp = 0; // No fixed TP, rely on trailing
   }
   else
   {
      sl = price + (StopLossPips * pip_value * point);
      
      if (TakeProfitPips > 0)
         tp = price - (TakeProfitPips * pip_value * point);
      else
         tp = 0; // No fixed TP, rely on trailing
   }
   
   sl = NormalizeDouble(sl, digits);
   if (tp > 0) tp = NormalizeDouble(tp, digits);
   
   //--- Validasi SL/TP distance
   double sl_distance_check = MathAbs(price - sl);
   double tp_distance_check = (tp > 0) ? MathAbs(price - tp) : 0;
   
   Print("=== Order Details ===");
   Print("Entry Price: ", price);
   Print("Stop Loss: ", sl, " (Distance: ", DoubleToString(sl_distance_check, digits), ")");
   if (tp > 0)
      Print("Take Profit: ", tp, " (Distance: ", DoubleToString(tp_distance_check, digits), ")");
   else
      Print("Take Profit: TRAILING ONLY (no fixed TP)");
   Print("Lot Size: ", lot_size);
   
   // Check minimum distance (broker requirement)
   int min_stop_level = (int)SymbolInfoInteger(CurrentSymbol, SYMBOL_TRADE_STOPS_LEVEL);
   if (min_stop_level > 0)
   {
      double min_distance = min_stop_level * point;
      if (sl_distance_check < min_distance)
      {
         Print("ERROR: SL too close to price. Min distance: ", min_distance);
         return;
      }
      if (tp > 0 && tp_distance_check < min_distance)
      {
         Print("ERROR: TP too close to price. Min distance: ", min_distance);
         return;
      }
   }
   
   //--- Open trade
   bool result;
   string comment = (order_type == ORDER_TYPE_BUY) ? "Pullback BUY" : "Pullback SELL";
   
   if (order_type == ORDER_TYPE_BUY)
      result = trade.Buy(lot_size, CurrentSymbol, 0, sl, tp, comment);
   else
      result = trade.Sell(lot_size, CurrentSymbol, 0, sl, tp, comment);
   
   if (result)
   {
      last_trade_time = TimeCurrent();
      daily_trades++;
      Print("✓ Trade Opened: ", comment);
      Print("  Entry: ", price, " | SL: ", sl);
      if (tp > 0)
         Print("  TP: ", tp, " (", DoubleToString(tp_distance_check/(pip_value*point), 1), " pips)");
      else
         Print("  TP: Trailing Only");
      Print("  SL Distance: ", DoubleToString(sl_distance_check/(pip_value*point), 1), " pips");
      Print("  Trailing will start at ", TrailingStart, " pips profit");
   }
   else
   {
      Print("✗ Trade Failed: ", trade.ResultRetcodeDescription());
      Print("  Error Code: ", trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
//| Check Pyramiding Opportunity (Add Position in Trend)             |
//+------------------------------------------------------------------+
void CheckPyramidingOpportunity()
{
   if (!UsePyramiding) return;
   
   int open_positions = CountOpenPositions();
   if (open_positions >= MaxPositions) return;
   
   double point = SymbolInfoDouble(CurrentSymbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(CurrentSymbol, SYMBOL_DIGITS);
   double pip_value = (digits == 3 || digits == 5) ? 10 : 1;
   
   //--- Get first position info
   ENUM_POSITION_TYPE first_type = WRONG_VALUE;
   double first_open = 0;
   double total_profit_pips = 0;
   
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (!position.SelectByIndex(i)) continue;
      if (position.Symbol() != CurrentSymbol || position.Magic() != MagicNumber) continue;
      
      if (first_type == WRONG_VALUE)
      {
         first_type = position.PositionType();
         first_open = position.PriceOpen();
      }
      
      // Calculate average profit
      double current_price = (position.PositionType() == POSITION_TYPE_BUY) ?
                            SymbolInfoDouble(CurrentSymbol, SYMBOL_BID) :
                            SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);
      
      double profit_distance = (position.PositionType() == POSITION_TYPE_BUY) ?
                              (current_price - position.PriceOpen()) :
                              (position.PriceOpen() - current_price);
      
      double profit_pips = profit_distance / (pip_value * point);
      total_profit_pips += profit_pips;
   }
   
   double avg_profit_pips = total_profit_pips / open_positions;
   
   //--- Check if profit enough to add position
   if (avg_profit_pips >= PyramidStep)
   {
      // Check bars since last trade (avoid too frequent pyramiding)
      int bars_since = (int)((TimeCurrent() - last_trade_time) / PeriodSeconds(EntryTF));
      if (bars_since < MinBarsSince) return;
      
      Print(">>> Pyramiding Opportunity <<<");
      Print("Current positions: ", open_positions, " | Avg profit: ", DoubleToString(avg_profit_pips, 1), " pips");
      
      // Add position in same direction
      if (first_type == POSITION_TYPE_BUY)
         OpenTrade(ORDER_TYPE_BUY);
      else
         OpenTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Manage Positions (Trailing + Break Even)                         |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double point = SymbolInfoDouble(CurrentSymbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(CurrentSymbol, SYMBOL_DIGITS);
   double pip_value = (digits == 3 || digits == 5) ? 10 : 1;
   
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (!position.SelectByIndex(i)) continue;
      if (position.Symbol() != CurrentSymbol || position.Magic() != MagicNumber) continue;
      
      double open_price = position.PriceOpen();
      double current_sl = position.StopLoss();
      ulong ticket = position.Ticket();
      
      if (position.PositionType() == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
         double profit_distance = bid - open_price;
         double profit_pips = profit_distance / (pip_value * point);
         
         //--- Move to Break Even
         if (profit_pips >= BreakEvenPips && current_sl < open_price)
         {
            double new_sl = open_price + (pip_value * point); // BE + 1 pip
            new_sl = NormalizeDouble(new_sl, digits);
            trade.PositionModify(ticket, new_sl, position.TakeProfit());
            Print("Break Even: SL moved to ", new_sl);
         }
         //--- Trailing Stop
         else if (profit_pips >= TrailingStart)
         {
            double new_sl = bid - (TrailingStop * pip_value * point);
            new_sl = NormalizeDouble(new_sl, digits);
            
            if (new_sl > current_sl && new_sl < bid)
            {
               trade.PositionModify(ticket, new_sl, position.TakeProfit());
               Print("Trailing: SL moved to ", new_sl, " (", DoubleToString(profit_pips, 1), " pips profit)");
            }
         }
      }
      else // SELL
      {
         double ask = SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);
         double profit_distance = open_price - ask;
         double profit_pips = profit_distance / (pip_value * point);
         
         //--- Move to Break Even
         if (profit_pips >= BreakEvenPips && (current_sl == 0 || current_sl > open_price))
         {
            double new_sl = open_price - (pip_value * point); // BE + 1 pip
            new_sl = NormalizeDouble(new_sl, digits);
            trade.PositionModify(ticket, new_sl, position.TakeProfit());
            Print("Break Even: SL moved to ", new_sl);
         }
         //--- Trailing Stop
         else if (profit_pips >= TrailingStart)
         {
            double new_sl = ask + (TrailingStop * pip_value * point);
            new_sl = NormalizeDouble(new_sl, digits);
            
            if ((current_sl == 0 || new_sl < current_sl) && new_sl > ask)
            {
               trade.PositionModify(ticket, new_sl, position.TakeProfit());
               Print("Trailing: SL moved to ", new_sl, " (", DoubleToString(profit_pips, 1), " pips profit)");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count Open Positions                                             |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (position.SelectByIndex(i) && position.Symbol() == CurrentSymbol && 
          position.Magic() == MagicNumber)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Reset Daily Stats                                                 |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   datetime current_day = iTime(CurrentSymbol, PERIOD_D1, 0);
   
   if (current_day != daily_reset_time)
   {
      daily_reset_time = current_day;
      daily_profit = 0.0;
      daily_trades = 0;
      
      HistorySelect(current_day, TimeCurrent());
      for (int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if (ticket > 0 && HistoryDealGetString(ticket, DEAL_SYMBOL) == CurrentSymbol &&
             HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber)
         {
            daily_profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Create Dashboard on Chart                                         |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   //--- Background Panel
   string bg_name = dashboard_name + "_BG";
   if (ObjectCreate(0, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, bg_name, OBJPROP_CORNER, corner_position);
      ObjectSetInteger(0, bg_name, OBJPROP_XDISTANCE, x_distance);
      ObjectSetInteger(0, bg_name, OBJPROP_YDISTANCE, y_distance);
      ObjectSetInteger(0, bg_name, OBJPROP_XSIZE, 350);
      ObjectSetInteger(0, bg_name, OBJPROP_YSIZE, 220);
      ObjectSetInteger(0, bg_name, OBJPROP_BGCOLOR, clrBlack);
      ObjectSetInteger(0, bg_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg_name, OBJPROP_COLOR, clrDodgerBlue);
      ObjectSetInteger(0, bg_name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, bg_name, OBJPROP_BACK, false);
      ObjectSetInteger(0, bg_name, OBJPROP_SELECTABLE, false);
   }
   
   //--- Title
   CreateLabel("Title", "PULLBACK TRADER BY ADAM", 15, clrDodgerBlue, 10, 10);
   
   //--- Strategy Info
   CreateLabel("Strategy", "Strategy: EMA Pullback + Pyramiding", 9, clrWhite, 10, 35);
   
   //--- Account Info
   CreateLabel("Balance_Label", "Balance:", 9, clrGray, 10, 60);
   CreateLabel("Balance_Value", "$0.00", 10, clrLime, 120, 60);
   
   CreateLabel("Equity_Label", "Equity:", 9, clrGray, 10, 80);
   CreateLabel("Equity_Value", "$0.00", 10, clrLime, 120, 80);
   
   CreateLabel("Profit_Label", "Total Profit:", 9, clrGray, 10, 100);
   CreateLabel("Profit_Value", "$0.00", 10, clrYellow, 120, 100);
   
   //--- Trade Info
   CreateLabel("Positions_Label", "Open Positions:", 9, clrGray, 10, 125);
   CreateLabel("Positions_Value", "0/3", 10, clrAqua, 140, 125);
   
   CreateLabel("DailyTrades_Label", "Daily Trades:", 9, clrGray, 10, 145);
   CreateLabel("DailyTrades_Value", "0/10", 10, clrAqua, 140, 145);
   
   CreateLabel("DailyPL_Label", "Daily P/L:", 9, clrGray, 10, 165);
   CreateLabel("DailyPL_Value", "$0.00", 10, clrYellow, 140, 165);
   
   //--- Risk Info
   CreateLabel("Risk_Label", "Risk per Trade:", 9, clrGray, 10, 190);
   CreateLabel("Risk_Value", "Lot: 0.01", 10, clrOrange, 140, 190);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Create Label Helper Function                                      |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int font_size, color clr, int x, int y)
{
   string label_name = dashboard_name + "_" + name;
   
   if (ObjectCreate(0, label_name, OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, label_name, OBJPROP_CORNER, corner_position);
      ObjectSetInteger(0, label_name, OBJPROP_XDISTANCE, x_distance + x);
      ObjectSetInteger(0, label_name, OBJPROP_YDISTANCE, y_distance + y);
      ObjectSetString(0, label_name, OBJPROP_TEXT, text);
      ObjectSetString(0, label_name, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, font_size);
      ObjectSetInteger(0, label_name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, label_name, OBJPROP_BACK, false);
      ObjectSetInteger(0, label_name, OBJPROP_SELECTABLE, false);
   }
}

//+------------------------------------------------------------------+
//| Update Dashboard Values                                           |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double total_profit = equity - balance;
   
   int open_positions = 0;
   double current_pl = 0.0;
   
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (position.SelectByIndex(i) && position.Symbol() == CurrentSymbol && 
          position.Magic() == MagicNumber)
      {
         current_pl += position.Profit() + position.Swap() + position.Commission();
         open_positions++;
      }
   }
   
   //--- Update values
   ObjectSetString(0, dashboard_name + "_Balance_Value", OBJPROP_TEXT, "$" + DoubleToString(balance, 2));
   ObjectSetString(0, dashboard_name + "_Equity_Value", OBJPROP_TEXT, "$" + DoubleToString(equity, 2));
   
   // Profit color
   color profit_color = (total_profit >= 0) ? clrLime : clrRed;
   ObjectSetString(0, dashboard_name + "_Profit_Value", OBJPROP_TEXT, "$" + DoubleToString(total_profit, 2));
   ObjectSetInteger(0, dashboard_name + "_Profit_Value", OBJPROP_COLOR, profit_color);
   
   // Positions
   ObjectSetString(0, dashboard_name + "_Positions_Value", OBJPROP_TEXT, 
                   IntegerToString(open_positions) + "/" + IntegerToString(MaxPositions));
   
   // Daily trades
   ObjectSetString(0, dashboard_name + "_DailyTrades_Value", OBJPROP_TEXT, 
                   IntegerToString(daily_trades) + "/" + IntegerToString(MaxDailyTrades));
   
   // Daily P/L
   color daily_color = (daily_profit >= 0) ? clrLime : clrRed;
   ObjectSetString(0, dashboard_name + "_DailyPL_Value", OBJPROP_TEXT, "$" + DoubleToString(daily_profit, 2));
   ObjectSetInteger(0, dashboard_name + "_DailyPL_Value", OBJPROP_COLOR, daily_color);
   
   // Risk
   string risk_text = UseFixedLot ? ("Lot: " + DoubleToString(FixedLotSize, 2)) : (DoubleToString(RiskPercent, 1) + "%");
   ObjectSetString(0, dashboard_name + "_Risk_Value", OBJPROP_TEXT, risk_text);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Delete Dashboard from Chart                                       |
//+------------------------------------------------------------------+
void DeleteDashboard()
{
   ObjectDelete(0, dashboard_name + "_BG");
   ObjectDelete(0, dashboard_name + "_Title");
   ObjectDelete(0, dashboard_name + "_Strategy");
   ObjectDelete(0, dashboard_name + "_Balance_Label");
   ObjectDelete(0, dashboard_name + "_Balance_Value");
   ObjectDelete(0, dashboard_name + "_Equity_Label");
   ObjectDelete(0, dashboard_name + "_Equity_Value");
   ObjectDelete(0, dashboard_name + "_Profit_Label");
   ObjectDelete(0, dashboard_name + "_Profit_Value");
   ObjectDelete(0, dashboard_name + "_Positions_Label");
   ObjectDelete(0, dashboard_name + "_Positions_Value");
   ObjectDelete(0, dashboard_name + "_DailyTrades_Label");
   ObjectDelete(0, dashboard_name + "_DailyTrades_Value");
   ObjectDelete(0, dashboard_name + "_DailyPL_Label");
   ObjectDelete(0, dashboard_name + "_DailyPL_Value");
   ObjectDelete(0, dashboard_name + "_Risk_Label");
   ObjectDelete(0, dashboard_name + "_Risk_Value");
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Display (keep for compatibility)                          |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   UpdateDashboard();
}
//+------------------------------------------------------------------+
