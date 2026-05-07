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
    file = uploaded_file
    return unless file

    result = importer_class.preview(file)
    render json: { data: result }
  rescue StandardError => e
    render_error(422, "unprocessable_entity", "Import preview failed: #{e.message}")
  end

  def import_commit
    file = uploaded_file
    return unless file

    result = importer_class.commit(file)
    render json: { data: result }
  rescue StandardError => e
    render_error(422, "unprocessable_entity", "Import commit failed: #{e.message}")
  end

  private

  def uploaded_file
    file = params[:file]
    unless file.respond_to?(:read)
      render_error(400, "bad_request", "Missing file upload (multipart field 'file')")
      return nil
    end
    file.rewind if file.respond_to?(:rewind)
    file
  end
end
