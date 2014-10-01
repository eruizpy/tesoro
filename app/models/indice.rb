# encoding: utf-8
class Indice < ActiveRecord::Base
  DENOMINACIONES = ['Costo de construcción', 'Materiales', 'Mano de obra']

  has_many :cuotas
  has_many :contratos_de_venta
  validates_presence_of :periodo, :denominacion, :valor
  validates_inclusion_of :denominacion, in: DENOMINACIONES
  validates_uniqueness_of :denominacion, scope: :periodo
  validates_numericality_of :valor

  # cuando se actualiza un índice a su valor definitivo deja de ser
  # temporal
#  before_update :ahora_es_definitivo
  after_update  :indexar_al_ultimo, :actualizar_cuotas

  def temporal?
    temporal
  end

  def self.hay_alguno_este_mes?(denominacion)
    where(denominacion: denominacion).
      where(periodo: Date.today.beginning_of_month).
      where(temporal: false).
      any?
  end

  def self.por_fecha_y_denominacion(fecha, denominacion)
    periodo = fecha.beginning_of_month

    # obtener el indice para este periodo
    indice = Indice.where(periodo: periodo).
      where(denominacion: denominacion).
      order(:periodo).
      first

    # si no existe ese indice
    if indice.nil?
      # obtener el último indice disponible
      indice_anterior = Indice.where(denominacion: denominacion).
        order(:periodo).last

      raise 'Faltan los indices' if indice_anterior.nil?

      # y crear un indice temporal con el valor del ultimo indice
      # disponible
      indice = Indice.new(temporal: true,
        denominacion: denominacion,
        periodo: periodo,
        valor: indice_anterior.valor)
      indice.save!
    end

    # devolver siempre un indice
    indice
  end

  private

    def ahora_es_definitivo
      self.temporal = false

      # no dejar que temporal devuelva false
      true
    end

    # actualiza el monto de las facturas cuando se modifica el indice
    def actualizar_cuotas
      Factura.transaction do
        cuotas.each do |cuota|
          if cuota.factura.present?
            cuota.factura.importe_neto = cuota.monto_actualizado
            cuota.factura.save!
          end
        end
      end
    end

    # cuando se actualiza este indice, todos los indices temporales
    # subsiguientes adoptan el valor actual
    def indexar_al_ultimo
      Indice.transaction do
        Indice.where(temporal: true).
          where('periodo > ?', periodo).each do |indice|

          indice.update(valor: valor)
        end
      end
    end
end
