
#include <Trade/Trade.mqh>

//--------------------Inputs-------------------- 

input group "%R Williams";
input int wpr_period = 14;              // Periodo de Williams
input int wpr_low_value = -80;          // Valor Bajo de Williams
input int wpr_high_value = -20;         // Valor Alto de Williams

input group "Keltner";
input int    keltner_ema_period = 20;   // Periodo de la EMA
input int    keltner_atr_period = 10;   // Periodo del ATR
input double keltner_multiplier = 2.0;  // Multiplicador del ATR
input bool   keltner_show_label = true; // Mostrar etiquetas
input double entry_break = 0;           // Entry Break

input group "⏰ Filtro horario";
input int start_hour = 8;               // Hora de inicio de operaciones
input int trade_duration = 8;           // Cantidad de horas de operacion

input group "💸 Posición";
input int max_spread_pips = 6;          // Spread Máximo en Pips
input int tp_pips = 200;                // Take Profit en Pips
input int sl_pips = 100;                // Stop Loss en Pips
input double lotaje = 0.1;              // Lotaje

//--------------------Handlers--------------------

int wpr_h;
int keltner_h;

//--------------------Buffers--------------------

double wpr[];
double keltner_up[];
double keltner_down[];

//--------------------Variables-------------------- 

CTrade trade;
ulong trade_ticket = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {

   wpr_h = iWPR(_Symbol, PERIOD_CURRENT, wpr_period);
   keltner_h = iCustom(_Symbol, PERIOD_CURRENT, "Free Indicators/Keltner Channel",
                            keltner_ema_period, keltner_atr_period, keltner_multiplier, keltner_show_label);
                            

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   
   CopyBuffer(wpr_h, 0, 1, 1, wpr);
   CopyBuffer(keltner_h, 0, 1, 1, keltner_up);
   CopyBuffer(keltner_h, 2, 1, 1, keltner_down);
   MqlDateTime time = {};
   TimeCurrent(time);
   
   if(!PositionSelectByTicket(trade_ticket)) {
      trade_ticket = 0;
   }
   
//----------------------Filtros--------------------------
   if (!DentroHorarioOperacion(time.hour)) {
      Print("Fuera de horario");
      return;
   }
   
   if(AltoSpread()) {
      Print("El spread supera el máximo establecido");
      return;
   }
   
   if(trade_ticket > 0) {
      Print("Ya hay operaciones abiertas");
      return;
   }
   
//----------------------Operaciones--------------------------

   //Print("Ultimo Cierre: ", ObtenerUltimoCierre(), " Keltner Up: ", keltner_up[0], " Keltner Down: ", keltner_down[0], " %R: ", wpr[0]);
   
   double close = ObtenerUltimoCierre();
   
   if(wpr[0] > wpr_high_value && close > keltner_up[0] * (1 + (_Point * entry_break))) {
      EjecutarVenta();
   }
   
   if(wpr[0] < wpr_low_value && close < keltner_down[0] * (1 - (_Point * entry_break))) {
      EjecutarCompra();
   }
  
}

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

bool AltoSpread() {
   double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   double Bid = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   
   return ((Ask-Bid) / _Point) > max_spread_pips;
}

double ObtenerUltimoCierre() {
    double close_price[];  // Array para almacenar los precios de cierre

    // Copiar el último precio de cierre (vela anterior)
    if (CopyClose(_Symbol, PERIOD_CURRENT, 1, 1, close_price) <= 0) {
        Print("Error al obtener el precio de cierre");
        return 0.0;  // Devolver 0 si hay error
    }
    return close_price[0];  // Retornar el último precio de cierre
}



//+------------------------------------------------------------------+
