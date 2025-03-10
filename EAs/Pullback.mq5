//+------------------------------------------------------------------+
//|                                              5-EMAs-Williams.mq5 |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>

#property description "Estrategia de pullback a la EMA."

//Inputs

input group "💹 Indicadores";
input int fast_ema_period = 50;        // Periodo EMA Rápida
input int slow_ema_period = 100;       // Periodo EMA Lenta
input int wpr_period = 14;             // Periodo %R
input int adx_period = 14;             // Periodo ADX
input int wpr_top = -20;               // Tope %R
input int wpr_bottom = -80;            // Piso %R
input int adx_value = 25;              // Filtro ADX

input group "Reversión";
input int velas_compra = 3;            // Velas para Compra      
input int velas_venta = 3;             // Velas para Venta
input int confirmacion = 2;            // Confirmacion de Cruce       

input group "⏰ Filtro horario";
input int start_hour = 8;              // Hora de inicio de operaciones
input int trade_duration = 8;          // Cantidad de horas de operacion

input group "💸 Posición";
input int max_spread_pips = 6;         // Spread Máximo en Pips
input int tp_pips = 25;                // Take Profit en Pips
input int sl_pips = 60;                // Stop Loss en Pips
input double lotaje = 0.1;             // Lotaje

//Handlers

int fast_ema_h;
int slow_ema_h;
int wpr_h;
int adx_h;

//Buffers

double fast_ema[];
double slow_ema[];
double wpr[];
double adx[];
//Variables

CTrade trade;
ulong trade_ticket = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   
   fast_ema_h = iMA(_Symbol, PERIOD_CURRENT, fast_ema_period, 1, MODE_EMA, PRICE_CLOSE);
   slow_ema_h = iMA(_Symbol, PERIOD_CURRENT, slow_ema_period, 1, MODE_EMA, PRICE_CLOSE);
   wpr_h = iWPR(_Symbol, PERIOD_CURRENT, wpr_period);
   adx_h = iADX(_Symbol, PERIOD_CURRENT, adx_period);
   
   ArraySetAsSeries(fast_ema, true);
   ArraySetAsSeries(slow_ema, true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {

   if(!PositionSelectByTicket(trade_ticket)) {
      trade_ticket = 0;
   }
   
   if(AltoSpread()) return;
   
   int cant = 1 + MathMax(velas_compra, velas_venta) + confirmacion;
   
   CopyBuffer(fast_ema_h, 0, 1, cant, fast_ema);
   CopyBuffer(slow_ema_h, 0, 1, cant, slow_ema);
   CopyBuffer(wpr_h, 0, 1, 1, wpr);
   CopyBuffer(adx_h, 0, 1, 1, adx);
   
   MqlDateTime time = {};
   TimeCurrent(time);
   
//----------------------Filtros--------------------------

   if(adx[0] <= adx_value) return;
   
   if (!DentroHorarioOperacion(time.hour)) {
      Print("Fuera de horario");
      return;
   }
   
   if(trade_ticket > 0) {
      Print("Ya hay una operacion abierta");
      return;
   }
   
//----------------------Operaciones--------------------------

   if(fast_ema[0] > slow_ema[0] && wpr[0] < wpr_bottom && PullbackAlcista()) {
      EjecutarCompra();
   }
   else if(fast_ema[0] < slow_ema[0] && wpr[0] > wpr_top && PullbackBajista()) {
      EjecutarVenta();
   }
   
}
//+------------------------------------------------------------------+

void EjecutarCompra() {
   double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   trade.Buy(lotaje, _Symbol, Ask, Ask - sl_pips * _Point, Ask + tp_pips * _Point, "SUPER MEGA LONG");
   trade_ticket = trade.ResultOrder();
}

void EjecutarVenta() {

   double Bid = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   trade.Sell(lotaje, _Symbol, Bid, Bid + sl_pips * _Point, Bid - tp_pips * _Point, "SUPER MEGA SHORT");
   trade_ticket = trade.ResultOrder();
   
}

bool DentroHorarioOperacion(int hora_actual) {
   int hora_fin = start_hour + trade_duration;
   if (hora_fin >= 24) hora_fin -= 24; // Asegura que no pase de las 24 horas

   if (start_hour < hora_fin) {
      return (hora_actual >= start_hour && hora_actual < hora_fin);
   } else {
      // Caso en el que el horario cruza la medianoche
      return (hora_actual >= start_hour || hora_actual < hora_fin);
   }
}

bool PullbackAlcista () {
   double close[];
   CopyClose(_Symbol, PERIOD_CURRENT, 2, 1, close);
   
   if(close[0] <= fast_ema[1]) return false;
   
   double lows[];
   CopyLow(_Symbol, PERIOD_CURRENT, 3, velas_compra - 1, lows);
   
   bool pullback = false;
   
   for(uint i = 0; i < lows.Size(); i++) {
      if(lows[i] <= fast_ema[i + 2]) pullback = true;
   }
   
   if(!pullback) return false;
   
   for(int i = 0; i < confirmacion; i++) {
      if(fast_ema[velas_compra + 1 + i] <= slow_ema[velas_compra + 1 + i]) return false;
   }
   return true;
}

bool PullbackBajista() {
   double close[];
   CopyClose(_Symbol, PERIOD_CURRENT, 2, 1, close);
   
   if(close[0] >= fast_ema[1]) return false;
   
   double highs[];
   CopyHigh(_Symbol, PERIOD_CURRENT, 3, velas_compra - 1, highs);
   
   bool pullback = false;
   
   for(uint i = 0; i < highs.Size(); i++) {
      if(highs[i] >= fast_ema[i + 2]) pullback = true;
   }
   
   if(!pullback) return false;
   
   for(int i = 0; i < confirmacion; i++) {
      if(fast_ema[velas_compra + 1 + i] >= slow_ema[velas_compra + 1 + i]) return false;
   }
   return true;
}

bool AltoSpread() {
   double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   double Bid = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   
   return ((Ask-Bid) / _Point) > max_spread_pips;
}