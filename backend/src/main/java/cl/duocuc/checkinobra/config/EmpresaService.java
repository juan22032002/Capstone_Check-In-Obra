package cl.duocuc.checkinobra.config;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

@Service
@Transactional
public class EmpresaService {

    private final EmpresaRepository empresaRepository;

    public EmpresaService(EmpresaRepository empresaRepository) {
        this.empresaRepository = empresaRepository;
    }

    public Empresa crear(String nombre, String rut) {
        rut = Rut.normalizar(rut);
        if (empresaRepository.existsByRut(rut)) {
            throw new IllegalStateException("Ya existe una empresa con ese RUT");
        }
        return empresaRepository.save(Empresa.builder().nombre(nombre).rut(rut).build());
    }

    @Transactional(readOnly = true)
    public List<Empresa> listar() {
        // Deja de listar todas las constructoras del sistema: cada quien ve la suya.
        return List.of(obtener(SesionActual.empresaId()));
    }

    /**
     * Solo lo usa el alta por migración. No hay endpoint que llegue acá: ver el
     * javadoc de {@link EmpresaController}.
     */

    @Transactional(readOnly = true)
    public Empresa obtener(Long id) {
        AccesoEmpresa.exigirEmpresa(id);
        return empresaRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Empresa no encontrada: " + id));
    }
}
