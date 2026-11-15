module TableTestHelper
  # The body cells under a column heading, across every table in the response.
  def column_cells(header)
    css_select("table").flat_map do |table|
      index = table.css("thead th").map { |th| th.text.strip }.index(header)
      next [] unless index

      table.css("tbody tr").map { |tr| tr.element_children[index] }
    end
  end
end
