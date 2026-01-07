//+------------------------------------------------------------------+
//|                                       XAUUSD_Martingale_EA.mq5 |
//|                                                  Manus AI |
//+------------------------------------------------------------------+
#property copyright "Manus AI"
#property link      "https://github.com/coler07/mql5-format"
#property version   "1.01"
#property description "Martingale EA for XAUUSD - No Visual Grid, Time Limit"
#property strict

//--- Include necessary libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Global Objects
CTrade trade;
CPositionInfo position;
string CurrentSymbol = _Symbol;
ENUM_TIMEFRAMES TimeFrame = PERIOD_M15;

//--- Input Parameters
input group "--- Strategy Settings ---"
input double InitialLot      = 0.01;      // Initial Lot Size
input double LotMultiplier   = 2.0;       // Lot Multiplier after loss
input int    TakeProfit      = 500;       // Take Profit in Points (50 pips)
input int    MaxOrders       = 8;         // Maximum consecutive losses
input int    MagicNumber     = 144401;    // Unique Magic Number

input group "--- Time Management ---"
input int    MaxHoldingMinutes = 240;     // Max holding time in minutes (4 hours)
input bool   UseTimeLimit      = true;    // Enable time limit for positions

input group "--- Trend Filter (Simple MA Crossover) ---"
input int    FastMAPeriod    = 10;        // Fast MA Period
input int    SlowMAPeriod    = 30;        // Slow MA Period
input ENUM_MA_METHOD MAMethod = MODE_EMA;  // MA Method

//--- Global Handles
int fast_ma_handle;
int slow_ma_handle;

//--- Global Variables
int consecutive_losses = 0;
datetime last_loss_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Check if the symbol is XAUUSD
   if (CurrentSymbol != "XAUUSD" && CurrentSymbol != "XAUUSDm")
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
   
   //--- Check time limit for open positions
   if (UseTimeLimit)
   {
      CheckTimeLimit();
   }
   
   //--- Get current open positions for this symbol and magic number
   int series_count = CountOpenPositions();
   
   //--- 1. Open Initial Trade (only if no open positions)
   if (series_count == 0)
   {
      CheckAndOpenInitialTrade();
   }
   
   //--- 2. Manage Take Profit (Virtual TP for all positions)
   CheckAndCloseSeries();
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
   
   //--- Calculate lot size based on consecutive losses
   double lot_size = CalculateLotSize();
   
   if (lot_size <= 0) 
   {
      Print("Cannot calculate lot size or max orders reached");
      return;
   }
   
   //--- Trend Up (Fast MA > Slow MA)
   if (fast_ma[1] > slow_ma[1])
   {
      if (trade.Buy(lot_size, CurrentSymbol, 0, 0, 0, "Martingale Buy #" + IntegerToString(consecutive_losses + 1)))
      {
         Print("Buy opened: Lot ", lot_size, " | Consecutive losses: ", consecutive_losses);
      }
   }
   //--- Trend Down (Fast MA < Slow MA)
   else if (fast_ma[1] < slow_ma[1])
   {
      if (trade.Sell(lot_size, CurrentSymbol, 0, 0, 0, "Martingale Sell #" + IntegerToString(consecutive_losses + 1)))
      {
         Print("Sell opened: Lot ", lot_size, " | Consecutive losses: ", consecutive_losses);
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on consecutive losses                   |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   //--- Check if max orders reached
   if (consecutive_losses >= MaxOrders)
   {
      Print("Max orders (", MaxOrders, ") reached. Waiting for reset...");
      return 0.0;
   }
   
   //--- Calculate lot based on martingale
   double lot = InitialLot * MathPow(LotMultiplier, consecutive_losses);
   
   //--- Normalize lot size to symbol specifications
   double min_lot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_STEP);
   
   lot = MathFloor(lot / step_lot) * step_lot;
   lot = NormalizeDouble(lot, 2);
   
   if (lot < min_lot) lot = min_lot;
   if (lot > max_lot) 
   {
      Print("Calculated lot (", lot, ") exceeds maximum (", max_lot, ")");
      lot = max_lot;
   }
   
   return lot;
}

//+------------------------------------------------------------------+
//| Check and Close All Positions if profit target reached           |
//+------------------------------------------------------------------+
void CheckAndCloseSeries()
{
   double total_profit = 0.0;
   int position_count = 0;
   
   //--- Calculate total profit for all positions
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (position.SelectByIndex(i))
      {
         if (position.Symbol() == CurrentSymbol && position.Magic() == MagicNumber)
         {
            total_profit += position.Profit();
            position_count++;
         }
      }
   }
   
   if (position_count == 0) return;
   
   //--- Calculate target profit
   // Simple approach: close if total profit >= $1.00 per initial lot
   double target_profit = 1.0 * (consecutive_losses + 1);
   
   if (total_profit >= target_profit)
   {
      //--- Close all positions
      CloseAllPositions();
      
      //--- Reset consecutive losses (profit achieved)
      Print("Target profit reached: $", DoubleToString(total_profit, 2), " | Resetting consecutive losses");
      consecutive_losses = 0;
      last_loss_time = 0;
   }
}

//+------------------------------------------------------------------+
//| Close All Positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (position.SelectByIndex(i))
      {
         if (position.Symbol() == CurrentSymbol && position.Magic() == MagicNumber)
         {
            trade.PositionClose(position.Ticket());
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
      if (position.SelectByIndex(i))
      {
         if (position.Symbol() == CurrentSymbol && position.Magic() == MagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check Time Limit for positions                                   |
//+------------------------------------------------------------------+
void CheckTimeLimit()
{
   datetime current_time = TimeCurrent();
   
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!position.SelectByIndex(i)) continue;
      if (position.Symbol() != CurrentSymbol || position.Magic() != MagicNumber) continue;
      
      datetime open_time = (datetime)position.Time();
      int holding_minutes = (int)((current_time - open_time) / 60);
      
      //--- If holding time exceeds limit
      if (holding_minutes >= MaxHoldingMinutes)
      {
         double profit = position.Profit();
         
         Print("Time limit exceeded (", holding_minutes, " min). Closing position. P/L: $", DoubleToString(profit, 2));
         
         trade.PositionClose(position.Ticket());
         
         //--- Update consecutive losses
         if (profit < 0)
         {
            consecutive_losses++;
            last_loss_time = current_time;
            
            if (consecutive_losses >= MaxOrders)
            {
               Print("WARNING: Max consecutive losses reached (", consecutive_losses, "/", MaxOrders, ")");
            }
         }
         else
         {
            //--- Profit or break-even, reset counter
            consecutive_losses = 0;
            last_loss_time = 0;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTrade - Track closed positions                                 |
//+------------------------------------------------------------------+
void OnTrade()
{
   //--- Check if position was closed
   if (HistorySelect(TimeCurrent() - 60, TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      
      for (int i = total - 1; i >= 0; i--)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if (ticket <= 0) continue;
         
         if (HistoryDealGetString(ticket, DEAL_SYMBOL) == CurrentSymbol &&
             HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber &&
             HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            
            //--- If closed with loss (and not closed by time limit already processed)
            if (profit < 0 && CountOpenPositions() == 0)
            {
               consecutive_losses++;
               last_loss_time = TimeCurrent();
               Print("Position closed with loss. Consecutive losses: ", consecutive_losses);
            }
            else if (profit >= 0 && CountOpenPositions() == 0)
            {
               //--- Profit achieved, reset
               consecutive_losses = 0;
               last_loss_time = 0;
               Print("Position closed with profit. Reset consecutive losses.");
            }
            
            break; // Process only the most recent deal
         }
      }
   }
}
//+------------------------------------------------------------------+