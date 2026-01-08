
//+------------------------------------------------------------------+
//|                                  XAUUSD Arrow Trader EA          |
//|                  Green Arrow Buy / Red Arrow Sell Logic          |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property version   "5.00" 
#property description "Trading berdasarkan Simulasi Panah (Rejection di Zona Support/Resistance)"
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
input bool   UseFixedLot     = true;      
input double FixedLotSize    = 0.01;      
input double RiskPercent     = 3.0;       
input int    StopLossPips    = 200;       
input int    TakeProfitPips  = 400;       
input int    TrailingStart   = 20;        
input int    TrailingStop    = 15;        
input int    BreakEvenPips   = 30;        

input group "=== Trend & Arrow Settings ==="
input int    EMA_Trend       = 100;       // EMA H1 untuk penentu tren besar
input int    MinBarsSince    = 2;          // Jarak minimal antar trade (dalam bar)

// --- Parameter Orderblock (Zona Support/Resistance) ---
input group "=== Orderblock (Zona Panah) Settings ==="
input int    OB_Lookback     = 10;        // Jumlah candle ke belakang untuk mencari zona terkuat
input double OB_PullbackThreshold = 0.5;  // Seberapa dekat harga harus menyentuh zona (dalam %)

input group "=== Pyramiding (Multiple Entries) ==="
input bool   UsePyramiding   = true;      
input int    MaxPositions    = 3;         
input int    PyramidStep     = 30;        

input group "=== Trade Management ==="
input int    MagicNumber     = 144406;    
input int    MaxDailyTrades  = 10;        
double MaxDailyLossPct = 5.0;       

input group "=== Partial Close Settings ==="
input bool  UsePartialClose = true;
input double PartialClosePercent = 50.0;
input int    PartialCloseAtPips  = 60;

//--- Global Handles
int h1_ema_handle;

// --- Variabel global untuk menyimpan Zona Support/Resistance ---
double last_buy_ob_high = 0;
double last_buy_ob_low = 0;
double last_sell_ob_high = 0;
double last_sell_ob_low = 0;

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
   h1_ema_handle = iMA(CurrentSymbol, TrendTF, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   
   if (h1_ema_handle == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return(INIT_FAILED);
   }
   
   Print("=== Arrow Trader Initialized ===");
   Print("Logic: Green Arrow (Buy) / Red Arrow (Sell)");
   
   //--- Create dashboard
   CreateDashboard();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (h1_ema_handle != INVALID_HANDLE) IndicatorRelease(h1_ema_handle);
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
   
   //--- Update status zona (Support/Resistance) di setiap bar baru
   UpdateOrderblocks();
   
   //--- Reset daily stats
   CheckDailyReset();
   
   //--- Check daily limits
   if (daily_trades >= MaxDailyTrades) return;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if (daily_profit <= -(balance * MaxDailyLossPct / 100.0)) return;
   
   //--- Manage existing positions (SL, TP, Trailing)
   ManagePositions();
   
   //--- Check if can open new trade
   int open_positions = CountOpenPositions();
   
   if (open_positions >= MaxPositions) return;
   
   // Check for pyramiding opportunity
   if (open_positions > 0 && UsePyramiding)
   {
      CheckPyramidingOpportunity();
   }
   
   // Check for new initial entry (LOGIKA PANAH DISINI)
   if (open_positions == 0)
   {
      //--- Check minimum bars between entries
      int bars_since = (int)((TimeCurrent() - last_trade_time) / PeriodSeconds(EntryTF));
      if (bars_since < MinBarsSince && last_trade_time > 0) return;
      
      //--- Cek sinyal Panah Hijau / Merah
      CheckArrowSignals();
   }
   
   //--- Update display
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Update Zona Support (Green) & Resistance (Red)                   |
//+------------------------------------------------------------------+
void UpdateOrderblocks()
{
   double current_bid = SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
   double current_ask = SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);

   // --- 1. CEK VALIDITAS ZONA ---
   // Jika harga menembus zona, maka zona dianggap tidak valid (broken)
   if (last_buy_ob_high > 0 && current_bid > last_buy_ob_high)
   {
      last_buy_ob_high = 0;
      last_buy_ob_low = 0;
   }
   if (last_sell_ob_low > 0 && current_ask < last_sell_ob_low)
   {
      last_sell_ob_high = 0;
      last_sell_ob_low = 0;
   }

   // --- 2. CARI ZONA BARU JIKA TIDAK ADA YANG VALID ---
   if (last_buy_ob_high == 0 || last_sell_ob_low == 0)
   {
      double high[], low[], close[], open[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(open, true);
      
      if (CopyHigh(CurrentSymbol, EntryTF, 0, OB_Lookback + 2, high) < OB_Lookback + 2) return;
      if (CopyLow(CurrentSymbol, EntryTF, 0, OB_Lookback + 2, low) < OB_Lookback + 2) return;
      if (CopyClose(CurrentSymbol, EntryTF, 0, OB_Lookback + 2, close) < OB_Lookback + 2) return;
      if (CopyOpen(CurrentSymbol, EntryTF, 0, OB_Lookback + 2, open) < OB_Lookback + 2) return;

      // Cari candle bullish terkuat untuk Zona Support (Buy OB)
      if (last_buy_ob_high == 0)
      {
         double max_range = 0;
         int strongest_candle_index = -1;
         for (int i = 1; i <= OB_Lookback; i++)
         {
            if (close[i] > open[i]) // Candle bullish
            {
               double candle_range = high[i] - low[i];
               if (candle_range > max_range)
               {
                  max_range = candle_range;
                  strongest_candle_index = i;
               }
            }
         }
         if (strongest_candle_index != -1)
         {
            last_buy_ob_high = high[strongest_candle_index];
            last_buy_ob_low = low[strongest_candle_index];
         }
      }

      // Cari candle bearish terkuat untuk Zona Resistance (Sell OB)
      if (last_sell_ob_low == 0)
      {
         double max_range = 0;
         int strongest_candle_index = -1;
         for (int i = 1; i <= OB_Lookback; i++)
         {
            if (close[i] < open[i]) // Candle bearish
            {
               double candle_range = high[i] - low[i];
               if (candle_range > max_range)
               {
                  max_range = candle_range;
                  strongest_candle_index = i;
               }
            }
         }
         if (strongest_candle_index != -1)
         {
            last_sell_ob_high = high[strongest_candle_index];
            last_sell_ob_low = low[strongest_candle_index];
         }
      }
   }
}

//+------------------------------------------------------------------+
//| LOGIKA UTAMA: Cek Panah Hijau (Buy) & Merah (Sell)               |
//+------------------------------------------------------------------+
void CheckArrowSignals()
{
   //--- Get H1 Trend EMA (Filter Trend)
   double h1_ema[];
   ArraySetAsSeries(h1_ema, true);
   if (CopyBuffer(h1_ema_handle, 0, 0, 2, h1_ema) < 2) return;
   double h1_close = iClose(CurrentSymbol, TrendTF, 1);
   bool h1_bullish = (h1_close > h1_ema[1]);
   bool h1_bearish = (h1_close < h1_ema[1]);
   
   //--- Data Candle M15 saat ini (index 1 karena bar baru sudah terbentuk di OnTick start)
   double open[], close[], high[], low[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   if (CopyOpen(CurrentSymbol, EntryTF, 0, 2, open) < 2) return;
   if (CopyClose(CurrentSymbol, EntryTF, 0, 2, close) < 2) return;
   if (CopyHigh(CurrentSymbol, EntryTF, 0, 2, high) < 2) return;
   if (CopyLow(CurrentSymbol, EntryTF, 0, 2, low) < 2) return;

   //--- Harga Saat Ini
   double current_bid = SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
   double current_ask = SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);

   // ==========================================
   // 1. LOGIKA BUY (GREEN ARROW)
   // ==========================================
   // Syarat: Tren Naik H1 + Harga di Zona Support + Candle Bullish (Rejection)
   if (h1_bullish && last_buy_ob_low > 0)
   {
      // Cek apakah harga menyentuh/masuk zona support
      double ob_range = last_buy_ob_high - last_buy_ob_low;
      double threshold = ob_range * OB_PullbackThreshold;
      
      // Apakah low candle menyentuh area support?
      bool touched_zone = (low[1] <= last_buy_ob_high + threshold && low[1] >= last_buy_ob_low - threshold);
      
      // Apakah candle berakhir hijau (Buy rejection)?
      bool green_candle = (close[1] > open[1]); 
      
      if (touched_zone && green_candle)
      {
         Print(">>> GREEN ARROW DETECTED (Buy Signal) <<<");
         Print("Price rejected Support Zone: [", last_buy_ob_low, " - ", last_buy_ob_high, "]");
         OpenTrade(ORDER_TYPE_BUY);
         return;
      }
   }
   
   // ==========================================
   // 2. LOGIKA SELL (RED ARROW)
   // ==========================================
   // Syarat: Tren Turun H1 + Harga di Zona Resistance + Candle Bearish (Rejection)
   if (h1_bearish && last_sell_ob_high > 0)
   {
      // Cek apakah harga menyentuh/masuk zona resistance
      double ob_range = last_sell_ob_high - last_sell_ob_low;
      double threshold = ob_range * OB_PullbackThreshold;
      
      // Apakah high candle menyentuh area resistance?
      bool touched_zone = (high[1] >= last_sell_ob_low - threshold && high[1] <= last_sell_ob_high + threshold);
      
      // Apakah candle berakhir merah (Sell rejection)?
      bool red_candle = (close[1] < open[1]);
      
      if (touched_zone && red_candle)
      {
         Print(">>> RED ARROW DETECTED (Sell Signal) <<<");
         Print("Price rejected Resistance Zone: [", last_sell_ob_low, " - ", last_sell_ob_high, "]");
         OpenTrade(ORDER_TYPE_SELL);
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Open Trade with Risk Management                                  |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE order_type)
{
   double point = SymbolInfoDouble(CurrentSymbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(CurrentSymbol, SYMBOL_DIGITS);
   double pip_value = (digits == 3 || digits == 5) ? 10 : 1;
   
   double lot_size;
   if (UseFixedLot) lot_size = FixedLotSize;
   else
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double risk_money = balance * (RiskPercent / 100.0);
      double tick_value = SymbolInfoDouble(CurrentSymbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(CurrentSymbol, SYMBOL_TRADE_TICK_SIZE);
      double sl_distance = StopLossPips * pip_value * point;
      lot_size = risk_money / ((StopLossPips * pip_value) * tick_value / tick_size);
   }
   
   double min_lot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_STEP);
   lot_size = MathFloor(lot_size / step_lot) * step_lot;
   lot_size = NormalizeDouble(lot_size, 2);
   if (lot_size < min_lot) lot_size = min_lot;
   if (lot_size > max_lot) lot_size = max_lot;
   
   double price = (order_type == ORDER_TYPE_BUY) ? 
                  SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK) : 
                  SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
   
   double sl, tp;
   if (order_type == ORDER_TYPE_BUY)
   {
      sl = price - (StopLossPips * pip_value * point);
      if (TakeProfitPips > 0) tp = price + (TakeProfitPips * pip_value * point); else tp = 0;
   }
   else
   {
      sl = price + (StopLossPips * pip_value * point);
      if (TakeProfitPips > 0) tp = price - (TakeProfitPips * pip_value * point); else tp = 0;
   }
   
   sl = NormalizeDouble(sl, digits);
   if (tp > 0) tp = NormalizeDouble(tp, digits);
   
   string comment = (order_type == ORDER_TYPE_BUY) ? "Arrow Signal BUY" : "Arrow Signal SELL";
   
   if (order_type == ORDER_TYPE_BUY) trade.Buy(lot_size, CurrentSymbol, 0, sl, tp, comment);
   else trade.Sell(lot_size, CurrentSymbol, 0, sl, tp, comment);
   
   if (trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      last_trade_time = TimeCurrent();
      daily_trades++;
      Print("✓ Trade Opened: ", comment);
   }
   else
   {
      Print("✗ Trade Failed: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Check Pyramiding Opportunity                                     |
//+------------------------------------------------------------------+
void CheckPyramidingOpportunity()
{
   if (!UsePyramiding) return;
   int open_positions = CountOpenPositions();
   if (open_positions >= MaxPositions) return;
   
   double point = SymbolInfoDouble(CurrentSymbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(CurrentSymbol, SYMBOL_DIGITS);
   double pip_value = (digits == 3 || digits == 5) ? 10 : 1;
   
   ENUM_POSITION_TYPE first_type = WRONG_VALUE;
   double total_profit_pips = 0;
   
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (!position.SelectByIndex(i)) continue;
      if (position.Symbol() != CurrentSymbol || position.Magic() != MagicNumber) continue;
      
      if (first_type == WRONG_VALUE) first_type = position.PositionType();
      
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
   
   if (avg_profit_pips >= PyramidStep)
   {
      int bars_since = (int)((TimeCurrent() - last_trade_time) / PeriodSeconds(EntryTF));
      if (bars_since < MinBarsSince) return;
      
      Print(">>> Pyramiding Opportunity <<<");
      if (first_type == POSITION_TYPE_BUY) OpenTrade(ORDER_TYPE_BUY);
      else OpenTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Manage Positions                                                 |
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
      double current_volume = position.Volume(); 
      
      if (UsePartialClose)
      {
         double current_price = (position.PositionType() == POSITION_TYPE_BUY) ? 
                               SymbolInfoDouble(CurrentSymbol, SYMBOL_BID) :
                               SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);
         
         double profit_distance = (position.PositionType() == POSITION_TYPE_BUY) ?
                                 (current_price - open_price) :
                                 (open_price - current_price);
         
         double profit_pips = profit_distance / (pip_value * point);
         
         double initial_lot = UseFixedLot ? FixedLotSize : 0.01; 
         if (profit_pips >= PartialCloseAtPips && MathAbs(current_volume - initial_lot) < 0.001)
         {
            double volume_to_close = NormalizeDouble(current_volume * (PartialClosePercent / 100.0), 2);
            double min_lot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_MIN);
            if (volume_to_close >= min_lot)
            {
               if (trade.PositionClosePartial(ticket, volume_to_close))
               {
                  if(position.SelectByIndex(i))
                  {
                     double new_sl = open_price;
                     new_sl = NormalizeDouble(new_sl, digits);
                     trade.PositionModify(ticket, new_sl, position.TakeProfit());
                  }
               }
               continue;
            }
         }
      }
      
      if (position.PositionType() == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
         double profit_distance = bid - open_price;
         double profit_pips = profit_distance / (pip_value * point);
         
         if (profit_pips >= BreakEvenPips && current_sl < open_price)
         {
            double new_sl = open_price + (pip_value * point); 
            new_sl = NormalizeDouble(new_sl, digits);
            trade.PositionModify(ticket, new_sl, position.TakeProfit());
         }
         
         if (profit_pips >= TrailingStart) 
         {
            double new_sl = bid - (TrailingStop * pip_value * point);
            new_sl = NormalizeDouble(new_sl, digits);
            if (new_sl > current_sl && new_sl < bid) trade.PositionModify(ticket, new_sl, position.TakeProfit());
         }
      }
      else // SELL
      {
         double ask = SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);
         double profit_distance = open_price - ask;
         double profit_pips = profit_distance / (pip_value * point);
         
         if (profit_pips >= BreakEvenPips && (current_sl == 0 || current_sl > open_price))
         {
            double new_sl = open_price - (pip_value * point); 
            new_sl = NormalizeDouble(new_sl, digits);
            trade.PositionModify(ticket, new_sl, position.TakeProfit());
         }
         
         if (profit_pips >= TrailingStart) 
         {
            double new_sl = ask + (TrailingStop * pip_value * point);
            new_sl = NormalizeDouble(new_sl, digits);
            if ((current_sl == 0 || new_sl < current_sl) && new_sl > ask) trade.PositionModify(ticket, new_sl, position.TakeProfit());
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
   
   CreateLabel("Title", "ARROW TRADER BY ADAM v5.00", 15, clrDodgerBlue, 10, 10);
   CreateLabel("Strategy", "Logic: Green Arrow Buy / Red Arrow Sell", 9, clrWhite, 10, 35);
   
   CreateLabel("Balance_Label", "Balance:", 9, clrGray, 10, 60);
   CreateLabel("Balance_Value", "$0.00", 10, clrLime, 120, 60);
   CreateLabel("Equity_Label", "Equity:", 9, clrGray, 10, 80);
   CreateLabel("Equity_Value", "$0.00", 10, clrLime, 120, 80);
   CreateLabel("Profit_Label", "Total Profit:", 9, clrGray, 10, 100);
   CreateLabel("Profit_Value", "$0.00", 10, clrYellow, 120, 100);
   CreateLabel("Positions_Label", "Open Positions:", 9, clrGray, 10, 125);
   CreateLabel("Positions_Value", "0/3", 10, clrAqua, 140, 125);
   CreateLabel("DailyTrades_Label", "Daily Trades:", 9, clrGray, 10, 145);
   CreateLabel("DailyTrades_Value", "0/10", 10, clrAqua, 140, 145);
   CreateLabel("DailyPL_Label", "Daily P/L:", 9, clrGray, 10, 165);
   CreateLabel("DailyPL_Value", "$0.00", 10, clrYellow, 140, 165);
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
   
   ObjectSetString(0, dashboard_name + "_Balance_Value", OBJPROP_TEXT, "$" + DoubleToString(balance, 2));
   ObjectSetString(0, dashboard_name + "_Equity_Value", OBJPROP_TEXT, "$" + DoubleToString(equity, 2));
   
   color profit_color = (total_profit >= 0) ? clrLime : clrRed;
   ObjectSetString(0, dashboard_name + "_Profit_Value", OBJPROP_TEXT, "$" + DoubleToString(total_profit, 2));
   ObjectSetInteger(0, dashboard_name + "_Profit_Value", OBJPROP_COLOR, profit_color);
   
   ObjectSetString(0, dashboard_name + "_Positions_Value", OBJPROP_TEXT, 
                   IntegerToString(open_positions) + "/" + IntegerToString(MaxPositions));
   
   ObjectSetString(0, dashboard_name + "_DailyTrades_Value", OBJPROP_TEXT, 
                   IntegerToString(daily_trades) + "/" + IntegerToString(MaxDailyTrades));
   
   color daily_color = (daily_profit >= 0) ? clrLime : clrRed;
   ObjectSetString(0, dashboard_name + "_DailyPL_Value", OBJPROP_TEXT, "$" + DoubleToString(daily_profit, 2));
   ObjectSetInteger(0, dashboard_name + "_DailyPL_Value", OBJPROP_COLOR, daily_color);
   
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
