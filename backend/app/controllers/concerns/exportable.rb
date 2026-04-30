# Provides a generic `#export` action mixed into a controller.
#
# The including controller must define:
#   - export_scope           -> the ActiveRecord::Relation (filtered + sorted)
#   - export_columns         -> Hash of "Header" => :attr | ->(row){...}
#   - export_filename(format)-> String (optional; default "<resource>-<date>.<fmt>")
#
# Route: GET /api/v1/<resource>/export?format=csv
module Exportable
  extend ActiveSupport::Concern

  def export
    format = (params[:format].presence || "csv").to_s.downcase
    unless %w[csv json xlsx].include?(format)
      return render_error(400, "bad_request", "Unsupported format: #{format}")
    end

    bytes = Exports::Generic.call(rows: export_scope, columns: export_columns, format: format)
    filename =
      respond_to?(:export_filename, true) ? send(:export_filename, format) : default_export_filename(format)

    send_data bytes,
              type: Exports::Generic.mime_type(format),
              disposition: %(attachment; filename="#{filename}"),
              filename: filename
  end

  private

  def default_export_filename(format)
    base = controller_name
    "#{base}-#{Date.current.iso8601}.#{format}"
  end
end
