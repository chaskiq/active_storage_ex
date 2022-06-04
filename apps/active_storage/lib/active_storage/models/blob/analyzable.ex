# frozen_string_literal: true

# require "active_storage/analyzer/null_analyzer"

defmodule ActiveStorage.Blob.Analyzable do
  import ActiveStorage.{RepoClient}

  defmacro __using__(_opts) do
    quote do
      # Extracts and stores metadata from the file associated with this blob using a relevant analyzer. Active Storage comes
      # with built-in analyzers for images and videos. See ActiveStorage::Analyzer::ImageAnalyzer and
      # ActiveStorage::Analyzer::VideoAnalyzer for information about the specific attributes they extract and the third-party
      # libraries they require.
      #
      # To choose the analyzer for a blob, Active Storage calls +accept?+ on each registered analyzer in order. It uses the
      # first analyzer for which +accept?+ returns true when given the blob. If no registered analyzer accepts the blob, no
      # metadata is extracted from it.
      #
      # In a Rails application, add or remove analyzers by manipulating +Rails.application.config.active_storage.analyzers+
      # in an initializer:
      #
      #   # Add a custom analyzer for Microsoft Office documents:
      #   Rails.application.config.active_storage.analyzers.append DOCXAnalyzer
      #
      #   # Remove the built-in video analyzer:
      #   Rails.application.config.active_storage.analyzers.delete ActiveStorage::Analyzer::VideoAnalyzer
      #
      # Outside of a Rails application, manipulate +ActiveStorage.analyzers+ instead.
      #
      # You won't ordinarily need to call this method from a Rails application. New blobs are automatically and asynchronously
      # analyzed via #analyze_later when they're attached for the first time.
      def analyze(blob) do
        IO.inspect("ANALIZE blob")

        metadata = blob.metadata |> Jason.decode!()

        encoded_metadata =
          metadata |> Map.merge(extract_metadata_via_analyzer(blob)) |> Jason.encode!()

        ActiveStorage.Blob.changeset(
          blob,
          %{metadata: encoded_metadata}
        )
        |> repo().update!()

        # update! metadata: metadata.merge(extract_metadata_via_analyzer)
      end

      # Enqueues an ActiveStorage::AnalyzeJob which calls #analyze, or calls #analyze inline based on analyzer class configuration.
      #
      # This method is automatically called for a blob when it's attached for the first time. You can call it to analyze a blob
      # again (e.g. if you add a new analyzer or modify an existing one).
      def analyze_later(blob) do
        if analyzer_class(blob).analyze_later? do
          ActiveStorage.AnalyzeJob.perform_later(%{blob_id: blob.id})
        else
          analyze(blob)
        end
      end

      # Returns true if the blob has been analyzed.
      def analyzed?(blob) do
        metadata = metadata(blob)
        metadata |> Map.get("analyzed")
      end

      def metadata(blob) do
        case blob.metadata do
          nil -> %{}
          _ -> blob.metadata |> Jason.decode!()
        end
      end

      def extract_metadata_via_analyzer(blob) do
        mod = analyzer(blob).__struct__
        mod.metadata(blob) |> Map.merge(%{"analyzed" => true})
      end

      def analyzer(blob) do
        analyzer_class(blob).new(blob)
      end

      def analyzer_class(blob) do
        ActiveStorage.analyzers()
        |> Enum.find(fn mod ->
          mod.accept?(blob)
        end) || ActiveStorage.Analyzer.NullAnalyzer

        # ActiveStorage.analyzers.detect { |klass| klass.accept?(self) } || ActiveStorage::Analyzer::NullAnalyzer
      end
    end
  end
end
