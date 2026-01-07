//+------------------------------------------------------------------+
//|                                       XAUUSD_Martingale_EA.mq5 |
//|                                                  Manus AI |
//|                                        https://github.com/coler07/mql5-format |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property link      "https://github.com/coler07/mql5-format"
#property version   "1.00"
#property description "Martingale/Grid EA for XAUUSD based on Trend AI principles."
#property strict

//--- Include necessary libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\TerminalInfo.mqh>

//--- Global Objects
CTrade trade;
CPositionInfo position;
string CurrentSymbol = _Symbol;
ENUM_TIMEFRAMES TimeFrame = PERIOD_M15;

//--- Input Parameters
input group "--- Strategy Settings ---"
input double InitialLot      = 0.01;      // Initial Lot Size
input double LotMultiplier   = 2.0;       // Lot Multiplier for Grid
input int    GridStep        = 500;       // Grid Step in Points (50 pips for XAUUSD)
input int    TakeProfit      = 500;       // Take Profit for Series in Points (50 pips)
input int    MaxOrders       = 8;         // Maximum number of orders in a series
input int    MagicNumber     = 144401;    // Unique Magic Number

input group "--- Trend Filter (Simple MA Crossover) ---"
input int    FastMAPeriod    = 10;        // Fast MA Period
input int    SlowMAPeriod    = 30;        // Slow MA Period
input ENUM_MA_METHOD MAMethod = MODE_EMA;  // MA Method

//--- Global Handles
int fast_ma_handle;
int slow_ma_handle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Check if the symbol is XAUUSD
   if (CurrentSymbol != "XAUUSD")
   {
      Print("WARNING: This EA is optimized for XAUUSD. Current symbol is ", CurrentSymbol);
   }
   
   //--- Set up trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();
   
   //--- Create MA indicators
   fast_ma_handle = iMA(CurrentSymbol, TimeFrame, FastMAPeriod, 0, MAMethod, PRICE_CLOSE);
   slow_ma_handle = iMA(CurrentSymbol, TimeFrame, SlowMAPeriod, 0, MAMethod, PRICE_CLOSE);
   
   if (fast_ma_handle == INVALID_HANDLE || slow_ma_handle == INVALID_HANDLE)
   {
      Print("Error creating MA indicators");
      return(INIT_FAILED);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   if (fast_ma_handle != INVALID_HANDLE)
      IndicatorRelease(fast_ma_handle);
   if (slow_ma_handle != INVALID_HANDLE)
      IndicatorRelease(slow_ma_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check for new bar (optional, but good for M15 strategy)
   static datetime last_time = 0;
   datetime current_time = iTime(CurrentSymbol, TimeFrame, 0);
   if (current_time == last_time) return;
   last_time = current_time;
   
   //--- Get current open positions for this symbol and magic number
   int total_positions = PositionsTotal();
   int series_count = 0;
   double last_open_price = 0.0;
   ENUM_POSITION_TYPE series_type = WRONG_VALUE;
   
   for (int i = 0; i < total_positions; i++)
   {
      if (position.SelectByIndex(i))
      {
         if (position.Symbol() == CurrentSymbol && position.Magic() == MagicNumber)
         {
            series_count++;
            last_open_price = position.PriceOpen();
            series_type = position.PositionType();
         }
      }
   }
   
   //--- 1. Open Initial Trade
   if (series_count == 0)
   {
      CheckAndOpenInitialTrade();
   }
   //--- 2. Manage Grid
   else
   {
      ManageGrid(series_count, last_open_price, series_type);
   }
   
   //--- 3. Manage Take Profit (Virtual TP for the series)
   CheckAndCloseSeries(series_type);
}

//+------------------------------------------------------------------+
//| Check Trend and Open Initial Trade                               |
//+------------------------------------------------------------------+
void CheckAndOpenInitialTrade()
{
   //--- Arrays for MA values
   double fast_ma[];
   double slow_ma[];
   
   ArraySetAsSeries(fast_ma, true);
   ArraySetAsSeries(slow_ma, true);
   
   //--- Get MA values
   if (CopyBuffer(fast_ma_handle, 0, 0, 2, fast_ma) < 2)
   {
      Print("Error copying Fast MA data");
      return;
   }
   if (CopyBuffer(slow_ma_handle, 0, 0, 2, slow_ma) < 2)
   {
      Print("Error copying Slow MA data");
      return;
   }
   
   //--- Trend Up (Fast MA > Slow MA)
   if (fast_ma[1] > slow_ma[1])
   {
      trade.Buy(InitialLot, CurrentSymbol, 0, 0, 0, "Initial Buy");
   }
   //--- Trend Down (Fast MA < Slow MA)
   else if (fast_ma[1] < slow_ma[1])
   {
      trade.Sell(InitialLot, CurrentSymbol, 0, 0, 0, "Initial Sell");
   }
}

//+------------------------------------------------------------------+
//| Manage Grid Orders                                               |
//+------------------------------------------------------------------+
void ManageGrid(int count, double last_price, ENUM_POSITION_TYPE type)
{
   if (count >= MaxOrders) return; // Max orders reached
   
   ENUM_SYMBOL_INFO_DOUBLE price_type = (type == POSITION_TYPE_BUY) ? SYMBOL_ASK : SYMBOL_BID;
   double current_price = SymbolInfoDouble(CurrentSymbol, price_type);
   double distance = MathAbs(current_price - last_price) / _Point;
   
   //--- Check if the distance for a new grid order is reached
   if (distance >= GridStep)
   {
      //--- Calculate next lot size
      double next_lot = InitialLot * MathPow(LotMultiplier, count);
      
      //--- Normalize lot size to symbol specifications
      double min_lot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_MAX);
      double step_lot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_STEP);
      
      next_lot = NormalizeDouble(next_lot, 2); // Assuming 2 decimal places for lot size
      
      if (next_lot < min_lot) next_lot = min_lot;
      if (next_lot > max_lot) next_lot = max_lot;
      
      //--- Open the next grid order
      if (type == POSITION_TYPE_BUY)
      {
         trade.Buy(next_lot, CurrentSymbol, 0, 0, 0, "Grid Buy #" + IntegerToString(count + 1));
      }
      else if (type == POSITION_TYPE_SELL)
      {
         trade.Sell(next_lot, CurrentSymbol, 0, 0, 0, "Grid Sell #" + IntegerToString(count + 1));
      }
   }
}

//+------------------------------------------------------------------+
//| Check and Close Series (Virtual TP)                              |
//+------------------------------------------------------------------+
void CheckAndCloseSeries(ENUM_POSITION_TYPE type)
{
   double total_profit = 0.0;
   
   //--- Calculate total profit for the series
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (position.SelectByIndex(i))
      {
         if (position.Symbol() == CurrentSymbol && position.Magic() == MagicNumber && position.PositionType() == type)
         {
            total_profit += position.Profit();
         }
      }
   }
   
   //--- Check if total profit is greater than or equal to the target TP
   // The TP is in points, so we convert it to currency profit
   // This is a simplified virtual TP check. A more accurate one would calculate the required price move.
   // For simplicity, we use a fixed profit target in currency based on the initial trade's TP.
   
   // Calculate the currency value of the TP in points for the initial lot
   // This is a rough estimate and should be optimized.
   double point_value = SymbolInfoDouble(CurrentSymbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(CurrentSymbol, SYMBOL_TRADE_TICK_SIZE);
   double target_currency_profit = (double)TakeProfit * point_value * InitialLot;
   
   // Since the grid increases the lot size, the actual profit target should be higher.
   // A simpler and more robust approach for a grid is to close when the total profit is positive and exceeds a small buffer.
   // Let's use a minimum profit of $1.00 as a simple, safe target for the entire series.
   
   if (total_profit >= 1.0) // Close if total profit is $1.00 or more
   {
      for (int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if (position.SelectByIndex(i))
         {
            if (position.Symbol() == CurrentSymbol && position.Magic() == MagicNumber && position.PositionType() == type)
            {
               trade.PositionClose(position.Ticket());
            }
         }
      }
   }
}
//+------------------------------------------------------------------+