# Branch scoping for console controllers. A user with branch_id set (a
# branch_manager / osb_operator) only sees rows for their branch; a user with
# branch_id nil (superadmin / national) sees everything.
#
# Usage in a controller:
#   def index
#     @stores = branch_scoped(Store.all)
#   end
# and guard member writes with `authorize_branch!(record)`.
module BranchScopable
  extend ActiveSupport::Concern

  included do
    helper_method :branch_filterable? if respond_to?(:helper_method)
  end

  # Constrain a relation to the branches the current user may see.
  # `column` lets callers point at a differently-named branch FK.
  def branch_scoped(relation, column: :branch_id)
    return relation if current_user&.all_branches?

    relation.where(column => current_user.accessible_branch_ids)
  end

  # Raise unless the record belongs to a branch the user can access.
  def authorize_branch!(record, column: :branch_id)
    return if current_user&.all_branches?

    branch_id = record.public_send(column)
    return if current_user.accessible_branch_ids.include?(branch_id)

    raise Authorization::AuthorizationError.new(record.class.name.underscore, "access")
  end

  # For forms: the branch a new record should default to.
  def default_branch_id
    current_user&.branch_id
  end

  def branch_filterable?
    current_user&.all_branches?
  end
end
