# encoding: utf-8
require 'test_helper'

class CuotaTest < ActiveSupport::TestCase
  setup do
    @indice = create(:indice, valor: 1100, periodo: '2014-04-01')
    @cv = create(:contrato_de_venta, indice: @indice, fecha: '2014-05-01')

    @cv.valid?
    @cv.agregar_pago_inicial(@cv.monto_total * 0.1)
    @cv.crear_cuotas(12)
  end

  test "es válida" do
    [ :build, :build_stubbed, :create].each do |metodo|
      assert_valid_factory metodo, :cuota
    end
  end

  test "necesita monto_original" do
    assert m = build(:cuota, monto_original_centavos: nil)
    assert_not m.save
  end

  test "necesita vencimiento" do
    assert m = build(:cuota, vencimiento: nil)
    assert_not m.save
  end

  test "necesita descripcion" do
    assert m = build(:cuota, descripcion: nil)
    assert_not m.save
  end

  test "el monto se actualiza en base al indice del mes anterior" do
    assert indice_siguiente = create(:indice, valor: 1200, periodo: '2014-05-01')

    assert cuota = @cv.cuotas.where(vencimiento: '2014-06-01').first

    assert_equal indice_siguiente, cuota.indice_actual
    assert_equal cuota.monto_original * (indice_siguiente.valor / @indice.valor), cuota.monto_actualizado
  end

  test "listar cuotas vencidas" do
    # todas las cuotas vencidas de acá a 5 meses
    assert_equal 5, Cuota.vencidas('2014-05-01'.to_time + 5.months).count
  end

  test "algunas cuotas están vencidas" do
    assert Cuota.vencidas.first.vencida?
  end

  test "las cuotas generan facturas de cobro" do
    c = @cv.cuotas.first
    assert c.generar_factura, c.errors.messages.inspect

    f = Factura.last

    assert_equal c.factura, f
    assert f.cobro?
    assert_equal c.monto_actualizado, f.importe_neto
    assert_equal c.tercero, f.tercero
    assert_equal c.obra, f.obra
    assert_equal c.vencimiento + 10.days, f.fecha_pago.to_date
  end

  test "las cuotas que no están vencidas se pagan al indice actual" do
    # la ultima cuota todavía no está vencida
    c = @cv.cuotas.last
    assert_not c.vencida?, c.vencimiento

    # el periodo actual suele ser el indice del mes anterior
    p = Time.now.change(sec: 0, min: 0, hour: 0, day: 1).to_date - 1.month

    # crear dos indices, el que corresponde y el de la fecha de
    # vencimiento de la cuota
    assert indice_posta = create(:indice, valor: 1200, periodo: p)
    assert indice_mal = create(:indice, valor: 1300, periodo: c.vencimiento)

    assert c.generar_factura, c.errors.messages.inspect

    f = Factura.last

    # la factura que se creó es la de la cuota...
    assert_equal c.factura, f
    # pero su fecha es la del periodo
    assert_not_equal c.vencimiento, f.fecha

    # y su valor es del monto_actualizado a ese periodo, no al del
    # vencimiento
    assert_equal c.monto_original * ( indice_posta.valor / @indice.valor ),
      f.importe_neto
  end

  test "a veces queremos especificar el indice de la factura" do
    c = @cv.cuotas.last
    assert_not c.vencida?, c.vencimiento

    p = Time.now.change(sec: 0, min: 0, hour: 0, day: 1).to_date + 5.months
    assert indice_cualquiera = create(:indice, valor: 1300, periodo: p)
    assert c.generar_factura(p), c.errors.messages.inspect

    f = Factura.last
    assert_equal c.monto_original * ( indice_cualquiera.valor / @indice.valor), f.importe_neto
  end

  test "si el indice no existe se crea uno temporal" do
    c = @cv.cuotas[2]

    assert c.generar_factura, c.errors.messages.inspect
    assert c.indice.temporal?
    # como no se creó ningún índice más el utilizado es el indice
    # original
    assert_equal @indice.valor, c.indice.valor

    factura_importe_original = c.factura.importe_neto
    c.indice.valor = c.indice.valor * 1.2

    assert c.indice.save
    assert_not_equal factura_importe_original, c.factura.reload.importe_neto
    assert_not_equal factura_importe_original, c.factura.importe_total
  end

  test "hay cuotas pendientes" do
    assert_equal 13, @cv.cuotas.pendientes.count
  end

  test "hay cuotas que ya estan emitidas" do
    assert_difference('@cv.cuotas.pendientes.count', -1) do
      @cv.cuotas.first.generar_factura
    end

    assert_equal 1, @cv.cuotas.emitidas.count
  end

end
