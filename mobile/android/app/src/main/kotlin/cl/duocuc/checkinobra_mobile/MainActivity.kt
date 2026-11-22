package cl.duocuc.checkinobra_mobile

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // El brillo se cambia solo en la ventana de la app, no en el ajuste del
    // sistema: no pide permisos y vuelve solo al salir de la app.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "checkinobra/pantalla")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "brilloMaximo" -> {
                        ajustarVentana(
                            WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL,
                            pantallaEncendida = true,
                        )
                        result.success(null)
                    }
                    "brilloNormal" -> {
                        ajustarVentana(
                            WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE,
                            pantallaEncendida = false,
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun ajustarVentana(brillo: Float, pantallaEncendida: Boolean) {
        val atributos = window.attributes
        atributos.screenBrightness = brillo
        window.attributes = atributos
        if (pantallaEncendida) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
}
