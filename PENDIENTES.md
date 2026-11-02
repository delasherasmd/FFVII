# Pendientes

- [x] **Proyectar películas de la PC al proyector por WiFi**: listo, en [`proyector/`](proyector/).
  - [ ] Identificar el proyector con `IdentificarProyector.exe` y adaptar el programa a ese modelo.
  - [ ] Pantalla de inicio del proyector sin publicidad, con menú tipo Netflix (depende del sistema que tenga).

- [x] **Controlar la luz del techo (Smart Life) desde la PC**: listo, en [`luces/`](luces/), con el cuarto en 3D.
  - [ ] Conectar la cuenta de Smart Life (pasos en la ventana del programa).
  - [ ] «Modo cine» de Proyectar: bajar la luz al empezar la película (ya está; probarlo con la luz real).
  - [ ] Cuando haya mudanza: modelar el cuarto nuevo en 3D.

- [ ] **Cambiar la estética del proyector**
  - Para empezar falta definir:
    - Marca y modelo del proyector, y qué sistema tiene (Android TV, Google TV, Linux propio…).
    - Qué se quiere cambiar: fondo de pantalla, launcher o pantalla de inicio, tema, íconos,
      apps visibles, logo de arranque… ¿O se refiere al aspecto de la ventana de `Proyectar`?
  - Si es Android, se puede instalar otro launcher y cambiar el fondo con ADB desde la PC.
