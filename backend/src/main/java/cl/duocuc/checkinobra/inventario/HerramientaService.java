package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaService;
import cl.duocuc.checkinobra.config.SesionActual;
import cl.duocuc.checkinobra.importacion.FilaPlanilla;
import cl.duocuc.checkinobra.importacion.LectorPlanilla;
import cl.duocuc.checkinobra.importacion.ResultadoImportacion;
import cl.duocuc.checkinobra.importacion.ResultadoImportacion.ErrorFila;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Set;
import java.util.stream.Collectors;

@Service
@Transactional
public class HerramientaService {

    private final HerramientaRepository herramientaRepository;
    private final EmpresaService empresaService;

    public HerramientaService(HerramientaRepository herramientaRepository, EmpresaService empresaService) {
        this.herramientaRepository = herramientaRepository;
        this.empresaService = empresaService;
    }

    public Herramienta crear(
            Long empresaId, String codigoQr, String nombre, String categoria, double valorReposicion) {
        // El código se guarda siempre en mayúsculas. Es el mismo dato escrito
        // de dos formas —la etiqueta impresa y lo que teclea quien la registra—
        // y sin normalizarlo "her-014" y "HER-014" conviven como dos
        // herramientas distintas que nadie puede distinguir en pantalla.
        codigoQr = codigoQr == null ? "" : codigoQr.trim().toUpperCase();
        if (codigoQr.isEmpty()) {
            throw new IllegalArgumentException("El código de la herramienta es obligatorio");
        }
        if (herramientaRepository.findByEmpresaIdAndCodigoQr(empresaId, codigoQr).isPresent()) {
            // Antes esto reventaba en la base con una violación de UNIQUE, que
            // llega a la app como un 500 sin explicación.
            throw new IllegalStateException("Ya existe una herramienta con ese código");
        }
        Empresa empresa = empresaService.obtener(empresaId);
        Herramienta herramienta = Herramienta.builder()
                .codigoQr(codigoQr)
                .nombre(nombre)
                .categoria(categoria)
                .valorReposicion(valorReposicion)
                .estado(EstadoHerramienta.DISPONIBLE)
                .empresa(empresa)
                .build();
        return herramientaRepository.save(herramienta);
    }

    @Transactional(readOnly = true)
    public List<Herramienta> listarPorEmpresa(Long empresaId) {
        AccesoEmpresa.exigirEmpresa(empresaId);
        return herramientaRepository.findByEmpresaId(empresaId);
    }

    @Transactional(readOnly = true)
    public Herramienta obtener(Long id) {
        return herramientaRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Herramienta no encontrada: " + id));
    }

    @Transactional(readOnly = true)
    public Herramienta buscarPorCodigoQr(String codigoQr) {
        return herramientaRepository.findByEmpresaIdAndCodigoQr(SesionActual.empresaId(), codigoQr.trim().toUpperCase())
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Código no reconocido"));
    }

    /**
     * Alta masiva desde una planilla Excel — mismo contrato que el catálogo de
     * materiales: se valida el archivo entero y se guarda solo si no quedó
     * ningún error y quien llama confirmó.
     *
     * @param confirmar {@code false} simula: no toca la base
     */
    public ResultadoImportacion importar(Long empresaId, InputStream planilla, boolean confirmar) {
        AccesoEmpresa.exigirEmpresa(empresaId);

        List<FilaPlanilla> filas = LectorPlanilla.leer(planilla, FilaHerramienta.ENCABEZADOS.size());
        if (filas.isEmpty()) {
            throw new IllegalArgumentException("La planilla no tiene ninguna fila con datos");
        }

        List<ErrorFila> errores = new ArrayList<>();
        List<FilaHerramienta> validas = new ArrayList<>();
        Set<String> codigosDelArchivo = new HashSet<>();
        Map<String, Integer> filaDelCodigo = new HashMap<>();

        for (FilaPlanilla fila : filas) {
            try {
                FilaHerramienta herramienta = FilaHerramienta.desde(fila);

                if (!codigosDelArchivo.add(herramienta.codigoQr())) {
                    throw new IllegalArgumentException(
                            "El código '" + herramienta.codigoQr() + "' se repite en la planilla");
                }

                filaDelCodigo.put(herramienta.codigoQr(), fila.numero());
                validas.add(herramienta);
            } catch (IllegalArgumentException e) {
                errores.add(new ErrorFila(fila.numero(), e.getMessage()));
            }
        }

        // Una consulta para todo el archivo, no una por fila.
        Set<String> yaExisten = codigosDelArchivo.isEmpty()
                ? Set.of()
                : herramientaRepository.findByEmpresaIdAndCodigoQrIn(empresaId, codigosDelArchivo).stream()
                        .map(Herramienta::getCodigoQr)
                        .collect(Collectors.toSet());

        validas.removeIf(herramienta -> {
            if (yaExisten.contains(herramienta.codigoQr())) {
                errores.add(new ErrorFila(
                        filaDelCodigo.get(herramienta.codigoQr()),
                        "Ya existe una herramienta con el código '" + herramienta.codigoQr() + "'"));
                return true;
            }
            return false;
        });

        errores.sort(Comparator.comparingInt(ErrorFila::fila));

        if (!errores.isEmpty()) {
            return ResultadoImportacion.conErrores(filas.size(), errores);
        }
        if (!confirmar) {
            return ResultadoImportacion.simulada(filas.size());
        }

        Empresa empresa = empresaService.obtener(empresaId);
        herramientaRepository.saveAll(validas.stream()
                .map(f -> Herramienta.builder()
                        .codigoQr(f.codigoQr())
                        .nombre(f.nombre())
                        .categoria(f.categoria())
                        .valorReposicion(f.valorReposicion())
                        // Una herramienta recién dada de alta está en bodega:
                        // no puede nacer prestada ni en mantención.
                        .estado(EstadoHerramienta.DISPONIBLE)
                        .empresa(empresa)
                        .build())
                .toList());
        return ResultadoImportacion.importada(validas.size());
    }
}
