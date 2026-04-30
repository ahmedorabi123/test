# Mixes generic `#import` (validate-only) and `#import_commit` actions into a controller.
#
# The including controller must define:
#   - importer_class   -> service class with .preview(csv_string) and .commit(csv_string)
#
# Routes:
#   POST /api/v1/<resource>/import           (multipart: file)   => preview
#   POST /api/v1/<resource>/import/commit    (multipart: file)   => commit
module Importable
  extend ActiveSupport::Concern

  def import
    csv_string = read_uploaded_file
    return unless csv_string

    result = importer_class.preview(csv_string)
    render json: { data: result }
  rescue StandardError => e
    render_error(422, "unprocessable_entity", "Import preview failed: #{e.message}")
  end

  def import_commit
    csv_string = read_uploaded_file
    return unless csv_string

    result = importer_class.commit(csv_string)
    render json: { data: result }
  rescue StandardError => e
    render_error(422, "unprocessable_entity", "Import commit failed: #{e.message}")
  end

  private

  def read_uploaded_file
    file = params[:file]
    unless file.respond_to?(:read)
      render_error(400, "bad_request", "Missing file upload (multipart field 'file')")
      return nil
    end
    content = file.read
    file.rewind if file.respond_to?(:rewind)
    content.force_encoding("UTF-8")
  end
end
