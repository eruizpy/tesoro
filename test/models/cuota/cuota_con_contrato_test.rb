# encoding: utf-8
require 'test_helper'

class CuotaConContratoTest < ActiveSupport::TestCase
  setup do
    # FIXME este setup es monstruoso, hasta hacía asserts??
    @cv = create(:contrato_de_venta, fecha: Date.today - 2.months)

    indice_viejo = create(:indice, :para_cuotas, periodo: (Date.today - 10.months).beginning_of_month)
    indice_viejo.save!

    @indice = @cv.indice_para(Date.today - 2.months)
    @cv.indice = @indice

    @cv.agregar_pago_inicial(@cv.fecha, @cv.monto_total * 0.2)

    @cv.agregar_cuota attributes_for(:cuota, monto_original: @cv.monto_total * 0.2, vencimiento: Date.today - 1.months)
    @cv.agregar_cuota attributes_for(:cuota, monto_original: @cv.monto_total * 0.2, vencimiento: Date.today - 1.days)
    @cv.agregar_cuota attributes_for(:cuota, monto_original: @cv.monto_total * 0.1, vencimiento: Date.today + 1.months)
    @cv.agregar_cuota attributes_for(:cuota, monto_original: @cv.monto_total * 0.1, vencimiento: Date.today + 2.months)
    @cv.agregar_cuota attributes_for(:cuota, monto_original: @cv.monto_total * 0.1, vencimiento: Date.today + 3.months)
    @cv.agregar_cuota attributes_for(:cuota, monto_original: @cv.monto_total * 0.1, vencimiento: Date.today + 4.months)

    @cv.save!
  end

  test 'el monto se actualiza en base al índice del mes anterior' do
    cuota = @cv.cuotas.sin_vencer.sample
    indice_siguiente = create(:indice, :para_cuotas, valor: 1200, periodo: @cv.periodo_para(cuota.vencimiento))

    assert_equal indice_siguiente, cuota.indice_actual
    assert_equal cuota.monto_original * (indice_siguiente.valor / @indice.valor), cuota.monto_actualizado
  end

  test 'listar cuotas vencidas' do
    assert_equal 2, @cv.cuotas.vencidas.count
  end

  test 'algunas cuotas están vencidas' do
    assert @cv.cuotas.vencidas.first.vencida?, @cv.cuotas.vencidas.inspect
  end

  test 'las cuotas que no están vencidas se pagan al índice actual' do
    c = @cv.cuotas.sin_vencer.pendientes.sample
    refute c.vencida?, c.vencimiento

    # crear dos índices, el que corresponde y el de la fecha de
    # vencimiento de la cuota
    indice_posta = @cv.indice_para(Date.today)

    f = c.generar_factura

    # la factura que se creó es la de la cuota...
    assert_equal c.factura, f
    # pero su fecha es la del periodo
    assert_not_equal c.vencimiento, f.fecha

    # y su valor es del monto_actualizado a ese periodo, no al del
    # vencimiento
    assert_equal c.monto_original * (indice_posta.valor / @indice.valor),
      f.importe_neto, [f, c.indice_actual(Date.today), @indice, indice_posta]
  end

  test 'a veces queremos especificar el índice de la factura' do
    c = @cv.cuotas.vencidas.sample
    # si la cuota no está vencida, Cuota.generar_factura siempre le va a
    # enchufar el mejor índice y no el que queremos
    assert c.vencida?, c.vencimiento

    # creamos un índice cualquiera en cualquier fecha
    p = (Date.today + 5.months).beginning_of_month
    indice_cualquiera = create(:indice, :para_cuotas, valor: 1300, periodo: p)

    # le decimos a la cuota que genere una factura en base a ese índice
    assert_instance_of Factura, c.generar_factura(p), c.errors.messages.inspect
    # Cuota.indice_actual(p) debería devolver el índice que creamos a
    # propósito
    assert_equal indice_cualquiera, c.indice
    assert f = c.factura, c.inspect
    assert_equal c.monto_original * (indice_cualquiera.valor / @indice.valor),
      f.importe_neto
  end

  test 'si el índice no existe se crea uno temporal' do
    c = @cv.cuotas.vencidas.pendientes.last

    assert c.generar_factura(c.vencimiento), c.errors.messages.inspect
    assert c.indice.temporal?, [c.inspect, c.indice.inspect]
    # como no se creó ningún índice más el utilizado es el índice
    # original
    assert_equal @indice.valor, c.indice.valor

    factura_importe_original = c.factura.importe_neto

    # al cambiar el valor del índice, se dispara la actualizacion de
    # montos de facturas por Indice.after_update
    c.indice.update(valor: c.indice.valor * 2, temporal: false)
    refute c.indice.temporal?
    assert c.factura.reload

    assert_not_equal factura_importe_original, c.factura.importe_neto
    assert_not_equal factura_importe_original, c.factura.importe_total
  end

  test 'hay cuotas pendientes' do
    # se crearon las cuotas pero no se generaron facturas para ninguna
    # por lo que todas están pendientes
    assert_equal @cv.cuotas.count, @cv.cuotas.pendientes.count
  end

  test 'hay cuotas que ya estan emitidas' do
    assert_difference('@cv.cuotas.pendientes.count', -1) do
      @cv.cuotas.first.generar_factura
    end

    assert_equal 1, @cv.cuotas.emitidas.count
  end
end
