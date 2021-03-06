# encoding: utf-8
# Representa una causa de movimientos con una única instancia en el sistema, a
# la cual no nos interesa seguirle el rastro (e.g. efectivo).
class CausaNoTrackeable
  include ActiveModel::Naming
  include ActiveModel::Validations

  # Datos necesarios para generar los movimientos
  attr_accessor :monto, :caja, :caja_id, :monto_aceptado,
                :caja_destino, :caja_destino_id

  # Crea una asociación falsa. Por ejemplo
  #
  #   has_many :movimientos, as: :causa
  #
  # en la clase Efectivo define:
  #
  #   def movimientos
  #     Movimiento.where(causa_type: 'Efectivo', causa_id: id)
  #   end
  def self.has_many(cosos, opciones)
    modelo = cosos.to_s.classify.constantize
    poliforma = opciones[:as]

    define_method cosos do
      modelo.where(
        "#{poliforma}_type" => self.class.name,
        "#{poliforma}_id" => id
      )
    end
  end

  # No definir ningún before_destroy para los no trackeables (no se destruyen!)
  def self.before_destroy(params)
  end

  def self.construir(params)
    datos = params.extract! :monto_moneda, :monto, :caja_id, :caja,
      :monto_aceptado, :monto_aceptado_moneda, :caja_destino_id
    new datos
  end

  def initialize(opciones = {})
    @caja = parsear_caja opciones[:caja], opciones[:caja_id]
    @caja_destino = parsear_caja(
      opciones[:caja_destino], opciones[:caja_destino_id])

    # TODO quitar opciones de carga!
    @monto = parsear_monto(
      opciones[:monto], opciones[:monto_moneda])
    @monto_aceptado = parsear_monto(
      opciones[:monto_aceptado], opciones[:monto_aceptado_moneda])
  end

  def caja_id
    caja.try :id
  end

  def caja_destino_id
    caja_destino.try :id
  end

  def trackeable?
    false
  end

  # Puedo ofrecer pesos (monto), o dólares (monto) aceptados como pesos
  # (monto_aceptado), intercambiando las monedas directamente
  def usar_para_pagar(recibo)
    # Si ofrezco una moneda a cambio de la correspondiente a la factura, tengo
    # que cambiarla
    if monto_aceptado.try :nonzero?
      # Cambiamos la moneda y asociamos el recibo al recibo interno
      caja.cambiar(monto, monto_aceptado).update(recibo: recibo)
      self.monto = monto_aceptado
    end

    # Extraigo de la caja ya sea el pago correcto, o el pago aceptado que
    # generó el cambio
    movimiento = caja.extraer(monto)
    movimiento.causa = self
    movimiento.recibo = recibo
    movimiento
  end

  # Puedo aceptar pesos (monto), o dólares (monto) aceptados como pesos
  # (monto_aceptado), intercambiando las monedas directamente
  def usar_para_cobrar(recibo)
    # El cambio es a la inversa que en pagos, porque necesitamos que quede
    # asentada la plata que nos dan en realidad
    if monto_aceptado.try :nonzero?
      caja.cambiar(monto_aceptado, monto).update(recibo: recibo)
      self.monto = monto_aceptado
    end

    movimiento = caja.depositar(monto)
    movimiento.causa = self
    movimiento.recibo = recibo
    movimiento
  end

  # Los siguientes métodos son necesarios para que rails genere la asociación
  # desde el `belongs_to` del otro modelo

  # Usamos siempre el mismo id
  def id
    1
  end

  def to_key
    [1]
  end

  def [](key)
    self.send(key)
  end

  def destroyed?
    false
  end

  def new_record?
    false
  end

  def self.primary_key
    'id'
  end

  def self.base_class
    self
  end

  def self.column_names
    []
  end

  def self.find(id)
    self.new
  end

  protected

    def parsear_monto(monto, moneda = nil)
      if monto.class == Money
        monto
      else
        Monetize.parse monto.to_s + moneda.to_s
      end
    end

    def parsear_caja(caja, id)
      if caja.present?
        caja
      elsif id.present?
        self.caja_id = id
        Caja.find(id)
      end
    end
end
